// v2 signaling server (ALPN `deskagent-sig/2`, TCP).
//
// Transport binding: u32-BE length prefix + UTF-8 JSON, max 1 MiB per frame.
// Field names mirror docs/PROTOCOL_V2_SPEC.md §3 IDL (snake_case of the proto
// fields) so a future protobuf codegen swap keeps semantics. Unknown ops get
// STATUS_UNSUPPORTED (`status: 8`) and the session continues — never a drop.
//
// Ops (client -> server, each answered on the same connection unless noted):
// - hello {version, build, platform, uuid} -> hello {negotiated_version, ttl}
//   or error VERSION_REJECTED when version < 2 (no silent fallback).
// - register {peer, capabilities, keep_alive} -> registered {keep_alive,
//   mapped_addr, nat_type} after Ed25519 PeerId verification (auth.rs).
// - heartbeat {} -> heartbeat_ack {} (server reaps after 3 missed intervals).
// - punch {target, ephemeral_pk, allow_relay} -> punch_response
//   {target_addrs, relay_only} to the initiator, plus punch_offer routed to
//   the target's connection when online (else TARGET_OFFLINE).
// - relay_select {target, session_id, target_hash} -> relay_selected
//   {relay_addr, ttl}. The relay address is the operator-configured public
//   address (DESKAGENT_CONTROL_RELAY_ADVERTISE), never a container-internal IP.
// - signal {to, payload} -> forwarded verbatim to `to` (session-negotiate and
//   ICE/SDP blobs ride here); TARGET_OFFLINE when unknown.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, Mutex};

/// Newest (and lowest accepted) signaling generation. Mirrors the proto
/// `ProtocolVersion.PROTOCOL_VERSION_2`; anything below is VERSION_REJECTED.
pub const SIGNAL_VERSION: u32 = 2;
/// Granted keep-alive seconds when the client asks for none/invalid.
pub const DEFAULT_KEEPALIVE_SECS: u64 = 45;
/// Missed heartbeats before a peer is reaped as OFFLINE.
pub const MISSED_HEARTBEAT_LIMIT: u32 = 3;
/// Allocation lifetime returned by relay_select (seconds).
pub const RELAY_ALLOC_TTL_SECS: u32 = 3600;
/// Max signaling frame: 1 MiB (signaling never carries media).
pub const MAX_FRAME_BYTES: usize = 1024 * 1024;

#[derive(Debug, Deserialize)]
pub struct PeerIdJson {
    pub peer_id: String,
    #[serde(default)]
    pub ed25519_pubkey: String,
    #[serde(default)]
    pub device_uuid: String,
    #[serde(default)]
    pub issued_at: u32,
    #[serde(default)]
    pub kx_version: u32,
    #[serde(default)]
    pub signature: String,
}

#[derive(Debug, Deserialize)]
struct ClientMsg {
    op: String,
    #[serde(default)]
    version: u32,
    #[serde(default)]
    peer: Option<PeerIdJson>,
    // Negotiated for real in SessionNegotiate (signal op); kept on the wire
    // struct so hello/register payloads stay spec-shaped.
    #[allow(dead_code)]
    #[serde(default)]
    capabilities: Vec<String>,
    #[serde(default)]
    keep_alive: u64,
    #[serde(default)]
    target: String,
    #[serde(default)]
    payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
struct ServerMsg {
    op: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<serde_json::Value>,
}

struct Peer {
    tx: mpsc::UnboundedSender<ServerMsg>,
    addr: SocketAddr,
}

pub struct SignalingState {
    peers: Mutex<HashMap<String, Peer>>,
    relay_advertise: String,
}

impl SignalingState {
    pub fn new(relay_advertise: String) -> Self {
        Self {
            peers: Mutex::new(HashMap::new()),
            relay_advertise,
        }
    }
}

fn ok(op: &str, message: serde_json::Value) -> ServerMsg {
    ServerMsg {
        op: op.to_string(),
        status: Some(1),
        message: Some(message),
    }
}

fn err(op: &str, status: u32, text: &str) -> ServerMsg {
    ServerMsg {
        op: op.to_string(),
        status: Some(status),
        message: Some(serde_json::json!({"error": text})),
    }
}

fn b64decode(s: &str) -> Result<Vec<u8>, String> {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    STANDARD
        .decode(s.trim())
        .map_err(|e| format!("base64 decode failed: {e}"))
}

async fn write_msg(stream: &mut TcpStream, msg: &ServerMsg) -> std::io::Result<()> {
    let bytes = serde_json::to_vec(msg)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    stream.write_u32(bytes.len() as u32).await?;
    stream.write_all(&bytes).await?;
    stream.flush().await
}

async fn read_msg(stream: &mut TcpStream) -> std::io::Result<serde_json::Value> {
    let len = stream.read_u32().await? as usize;
    if len == 0 || len > MAX_FRAME_BYTES {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "frame length out of range",
        ));
    }
    let mut buf = vec![0u8; len];
    stream.read_exact(&mut buf).await?;
    serde_json::from_slice(&buf)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
}

async fn handle_conn(
    state: Arc<SignalingState>,
    mut stream: TcpStream,
    addr: SocketAddr,
) -> std::io::Result<()> {
    let (tx, mut rx) = mpsc::unbounded_channel::<ServerMsg>();
    let mut registered_id: Option<String> = None;
    let mut missed: u32 = 0;
    let mut keep_alive = DEFAULT_KEEPALIVE_SECS;
    loop {
        tokio::select! {
            out = rx.recv() => {
                match out {
                    Some(msg) => write_msg(&mut stream, &msg).await?,
                    None => break,
                }
            }
            res = read_msg(&mut stream) => {
                let value = match res {
                    Ok(v) => v,
                    Err(_) => break, // EOF or framing error: drop the connection
                };
                let msg: ClientMsg = match serde_json::from_value(value) {
                    Ok(m) => m,
                    Err(_) => {
                        write_msg(&mut stream, &err("error", 8, "unknown op")).await?;
                        continue;
                    }
                };
                match msg.op.as_str() {
                    "hello" => {
                        if msg.version != 0 && msg.version < SIGNAL_VERSION {
                            write_msg(&mut stream, &err("hello", 4, "version rejected: v2 floor")).await?;
                        } else {
                            write_msg(&mut stream, &ok("hello", serde_json::json!({
                                "negotiated_version": SIGNAL_VERSION, "ttl": 3600
                            }))).await?;
                        }
                    }
                    "register" => {
                        let peer = match msg.peer {
                            Some(p) => p,
                            None => {
                                write_msg(&mut stream, &err("registered", 3, "missing peer claim")).await?;
                                continue;
                            }
                        };
                        let now = crate::db::now();
                        let verified = (|| -> Result<(), String> {
                            let pk = b64decode(&peer.ed25519_pubkey)?;
                            let uuid = b64decode(&peer.device_uuid)?;
                            let sig = b64decode(&peer.signature)?;
                            crate::auth::verify_peer_id(
                                if msg.version == 0 { SIGNAL_VERSION } else { msg.version },
                                &peer.peer_id, &pk, &uuid, peer.issued_at,
                                if peer.kx_version == 0 { 2 } else { peer.kx_version },
                                &sig, now,
                            )
                        })();
                        if let Err(e) = verified {
                            write_msg(&mut stream, &err("registered", 3, &e)).await?;
                            continue;
                        }
                        if msg.version != 0 && msg.version < SIGNAL_VERSION {
                            write_msg(&mut stream, &err("registered", 4, "version rejected")).await?;
                            continue;
                        }
                        keep_alive = msg.keep_alive.clamp(15, 300);
                        missed = 0;
                        registered_id = Some(peer.peer_id.clone());
                        state.peers.lock().await.insert(peer.peer_id.clone(), Peer { tx: tx.clone(), addr });
                        write_msg(&mut stream, &ok("registered", serde_json::json!({
                            "keep_alive": keep_alive,
                            "mapped_addr": addr.to_string(),
                            "nat_type": 0
                        }))).await?;
                    }
                    "heartbeat" => {
                        missed = 0;
                        write_msg(&mut stream, &ok("heartbeat_ack", serde_json::json!({}))).await?;
                    }
                    "punch" => {
                        if registered_id.is_none() {
                            write_msg(&mut stream, &err("punch_response", 3, "register first")).await?;
                            continue;
                        }
                        let peers = state.peers.lock().await;
                        match peers.get(&msg.target) {
                            Some(target) => {
                                let from = registered_id.clone().unwrap_or_default();
                                let _ = target.tx.send(ok("punch_offer", serde_json::json!({
                                    "from": from, "payload": msg.payload, "relay_only": false
                                })));
                                write_msg(&mut stream, &ok("punch_response", serde_json::json!({
                                    "target_addrs": [target.addr.to_string()], "relay_only": false
                                }))).await?;
                            }
                            None => {
                                write_msg(&mut stream, &err("punch_response", 5, "target offline")).await?;
                            }
                        }
                    }
                    "relay_select" => {
                        if registered_id.is_none() {
                            write_msg(&mut stream, &err("relay_selected", 3, "register first")).await?;
                            continue;
                        }
                        let relay = state.relay_advertise.clone();
                        write_msg(&mut stream, &ok("relay_selected", serde_json::json!({
                            "relay_addr": relay, "ttl": RELAY_ALLOC_TTL_SECS
                        }))).await?;
                    }
                    "signal" => {
                        if registered_id.is_none() {
                            write_msg(&mut stream, &err("error", 3, "register first")).await?;
                            continue;
                        }
                        let peers = state.peers.lock().await;
                        match peers.get(&msg.target) {
                            Some(target) => {
                                let from = registered_id.clone().unwrap_or_default();
                                let _ = target.tx.send(ok("signal", serde_json::json!({
                                    "from": from, "payload": msg.payload
                                })));
                            }
                            None => {
                                write_msg(&mut stream, &err("error", 5, "target offline")).await?;
                            }
                        }
                    }
                    _ => {
                        write_msg(&mut stream, &err("error", 8, "unknown op")).await?;
                    }
                }
            }
            _ = tokio::time::sleep(tokio::time::Duration::from_secs(keep_alive)) => {
                missed += 1;
                if missed >= MISSED_HEARTBEAT_LIMIT {
                    break; // 3 missed keep-alive windows -> OFFLINE
                }
            }
        }
    }
    if let Some(id) = registered_id {
        let mut peers = state.peers.lock().await;
        // Only remove when the entry is still ours (a re-register replaced tx).
        let ours = peers.get(&id).map(|p| p.addr == addr).unwrap_or(false);
        if ours {
            peers.remove(&id);
        }
    }
    Ok(())
}

pub async fn serve(
    bind: &str,
    relay_advertise: &str,
) -> std::io::Result<()> {
    let listener = TcpListener::bind(bind).await?;
    eprintln!("signaling (deskagent-sig/2) on {bind}, relay advertise {relay_advertise}");
    let state = Arc::new(SignalingState::new(relay_advertise.to_string()));
    loop {
        let (stream, addr) = listener.accept().await?;
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = handle_conn(state, stream, addr).await {
                eprintln!("signaling {addr}: {e}");
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_op_is_unsupported_not_fatal() {
        let m = err("error", 8, "unknown op");
        assert_eq!(m.status, Some(8));
    }

    #[tokio::test]
    async fn hello_rejects_v1_and_accepts_v2() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            let (stream, peer) = listener.accept().await.unwrap();
            let state = Arc::new(SignalingState::new("127.0.0.1:34117".into()));
            handle_conn(state, stream, peer).await.unwrap();
        });
        let mut s = TcpStream::connect(addr).await.unwrap();
        // v1 hello -> VERSION_REJECTED (status 4).
        let v1 = serde_json::json!({"op":"hello","version":1});
        let b = serde_json::to_vec(&v1).unwrap();
        s.write_u32(b.len() as u32).await.unwrap();
        s.write_all(&b).await.unwrap();
        let reply = read_msg(&mut s).await.unwrap();
        assert_eq!(reply["status"], 4);
        // v2 hello -> ok.
        let v2 = serde_json::json!({"op":"hello","version":2});
        let b = serde_json::to_vec(&v2).unwrap();
        s.write_u32(b.len() as u32).await.unwrap();
        s.write_all(&b).await.unwrap();
        let reply = read_msg(&mut s).await.unwrap();
        assert_eq!(reply["status"], 1);
        assert_eq!(reply["message"]["negotiated_version"], 2);
    }
}
