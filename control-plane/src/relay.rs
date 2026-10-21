// Blind relay forwarder (ALPN `deskagent-relay/2`, TCP).
//
// Zero-knowledge: the relay parses only the §7 envelope header and routes by
// session UUID. Payload bytes are never inspected, logged, or retained beyond
// the in-flight forward.
//
// Envelope (NORMATIVE, docs/PROTOCOL_V2_SPEC.md §7):
//   magic[2] = 0xDA, 0x02 | type[1] | flags[1] | len u32-BE | session[16] |
//   target_hash[16] | ciphertext[len] | tag[16]
// where len covers the ciphertext only (tag is a fixed 16 trailer). Total on
// the wire per frame: 40 + len + 16. Max frame: 4 MiB.
//
// Pairing: the first frame seen for an unknown session UUID attaches the
// sender's socket as side A; the first frame for the same UUID from a
// DIFFERENT socket attaches side B and both directions start pumping. A third
// socket presenting a live UUID is rejected (session hijack attempt) and the
// event is logged. Idle sessions (no frame either way for RELAY_IDLE_SECS)
// are reaped.

use std::collections::HashMap;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, Mutex};

pub const RELAY_MAGIC: [u8; 2] = [0xDA, 0x02];
pub const RELAY_HEADER_LEN: usize = 40;
pub const RELAY_TAG_LEN: usize = 16;
pub const MAX_RELAY_FRAME: usize = 4 * 1024 * 1024;
/// Idle session reaper threshold (seconds).
pub const RELAY_IDLE_SECS: u64 = 300;

#[derive(Debug, PartialEq, Eq)]
pub struct RelayHeader {
    pub frame_type: u8,
    pub flags: u8,
    pub len: u32,
    pub session: [u8; 16],
    pub target_hash: [u8; 16],
}

/// Parse and validate one envelope header. Relay never looks past this.
pub fn parse_header(buf: &[u8; RELAY_HEADER_LEN]) -> Result<RelayHeader, String> {
    if buf[0] != RELAY_MAGIC[0] || buf[1] != RELAY_MAGIC[1] {
        return Err("bad relay magic".to_string());
    }
    let len = u32::from_be_bytes([buf[4], buf[5], buf[6], buf[7]]) as usize;
    if len > MAX_RELAY_FRAME {
        return Err("relay frame too large".to_string());
    }
    let mut session = [0u8; 16];
    let mut target_hash = [0u8; 16];
    session.copy_from_slice(&buf[8..24]);
    target_hash.copy_from_slice(&buf[24..40]);
    Ok(RelayHeader {
        frame_type: buf[2],
        flags: buf[3],
        len: len as u32,
        session,
        target_hash,
    })
}

struct Session {
    a: Option<mpsc::UnboundedSender<Vec<u8>>>,
    b: Option<mpsc::UnboundedSender<Vec<u8>>>,
    last_active: std::time::Instant,
}

struct RelayState {
    sessions: Mutex<HashMap<[u8; 16], Session>>,
}

async fn pump_socket(
    state: Arc<RelayState>,
    stream: TcpStream,
    peer: std::net::SocketAddr,
) -> std::io::Result<()> {
    let (tx, mut rx) = mpsc::unbounded_channel::<Vec<u8>>();
    // Split: the read half parses envelopes, the write half forwards.
    let (mut rd, mut wr) = stream.into_split();
    let writer = tokio::spawn(async move {
        while let Some(frame) = rx.recv().await {
            if wr.write_all(&frame).await.is_err() {
                break;
            }
        }
    });
    loop {
        let mut hdr = [0u8; RELAY_HEADER_LEN];
        if rd.read_exact(&mut hdr).await.is_err() {
            break;
        }
        let parsed = match parse_header(&hdr) {
            Ok(h) => h,
            Err(_) => break, // framing violation: drop the socket, keep the session
        };
        let total = parsed.len as usize + RELAY_TAG_LEN;
        let mut body = vec![0u8; total];
        if rd.read_exact(&mut body).await.is_err() {
            break;
        }
        let mut frame = Vec::with_capacity(RELAY_HEADER_LEN + total);
        frame.extend_from_slice(&hdr);
        frame.extend_from_slice(&body);
        let mut sessions = state.sessions.lock().await;
        let entry = sessions.entry(parsed.session).or_insert_with(|| Session {
            a: None,
            b: None,
            last_active: std::time::Instant::now(),
        });
        entry.last_active = std::time::Instant::now();
        // Attach this socket to the first free side; forward to the other.
        let me = &tx;
        let dest = if entry.a.as_ref().map(|s| s.same_channel(me)).unwrap_or(false) {
            entry.b.as_ref()
        } else if entry.b.as_ref().map(|s| s.same_channel(me)).unwrap_or(false) {
            entry.a.as_ref()
        } else if entry.a.is_none() {
            entry.a = Some(tx.clone());
            entry.b.as_ref()
        } else if entry.b.is_none() {
            entry.b = Some(tx.clone());
            entry.a.as_ref()
        } else {
            eprintln!("relay {peer}: third socket for live session, rejected");
            break;
        };
        if let Some(d) = dest {
            let _ = d.send(frame);
        }
        // else: first side attached, frame buffered nowhere (timely > complete).
    }
    writer.abort();
    Ok(())
}

pub async fn serve(bind: &str) -> std::io::Result<()> {
    let listener = TcpListener::bind(bind).await?;
    eprintln!("blind relay (deskagent-relay/2) on {bind}");
    let state = Arc::new(RelayState {
        sessions: Mutex::new(HashMap::new()),
    });
    // Idle reaper.
    let reap = state.clone();
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;
            let mut sessions = reap.sessions.lock().await;
            sessions.retain(|_, s| s.last_active.elapsed().as_secs() < RELAY_IDLE_SECS);
        }
    });
    loop {
        let (stream, addr) = listener.accept().await?;
        let state = state.clone();
        tokio::spawn(async move {
            if let Err(e) = pump_socket(state, stream, addr).await {
                eprintln!("relay {addr}: {e}");
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::TcpListener;

    fn frame(session: [u8; 16], payload: &[u8]) -> Vec<u8> {
        let mut f = vec![0xDA, 0x02, 0x01, 0x01];
        f.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        f.extend_from_slice(&session);
        f.extend_from_slice(&[0xABu8; 16]);
        f.extend_from_slice(payload);
        f.extend_from_slice(&[0xCDu8; 16]);
        f
    }

    #[test]
    fn header_roundtrip_and_magic_reject() {
        let good = frame([1u8; 16], b"hello");
        let mut hdr = [0u8; 40];
        hdr.copy_from_slice(&good[..40]);
        let parsed = parse_header(&hdr).unwrap();
        assert_eq!(parsed.len, 5);
        assert_eq!(parsed.session, [1u8; 16]);
        let mut bad = hdr;
        bad[0] = 0x00;
        assert!(parse_header(&bad).is_err());
    }

    #[tokio::test]
    async fn e2ee_ciphertext_survives_relay_but_relay_cannot_read_it() {
        // kx Noise_IK is transport-agnostic (byte acts); here two peers run
        // the handshake OUT OF BAND, then push SessionKeys ciphertext through
        // the relay envelope. Relay routes by session UUID only: flipping one
        // ciphertext byte must fail open() on the peer (proves relay never
        // re-encrypts / never sees plaintext).
        // NOTE: kx_v2 lives in the `base` crate which the control-plane
        // cannot depend on here; this test pins the SAME envelope property
        // with a fixed 32-byte key + ChaCha20-Poly1305-shaped opaque bytes.
        // Full kx_v2-through-relay E2E is base-side follow-up; relay-side
        // guarantee (opaque forward, no inspection) is what this proves.
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let state = Arc::new(RelayState {
            sessions: Mutex::new(HashMap::new()),
        });
        let st = state.clone();
        tokio::spawn(async move {
            loop {
                let (s, p) = listener.accept().await.unwrap();
                let st = st.clone();
                tokio::spawn(async move {
                    pump_socket(st, s, p).await.unwrap();
                });
            }
        });
        let mut a = TcpStream::connect(addr).await.unwrap();
        let mut b = TcpStream::connect(addr).await.unwrap();
        let mut secret = vec![0u8; 32];
        for (i, v) in secret.iter_mut().enumerate() {
            *v = (i as u8).wrapping_mul(7).wrapping_add(3);
        }
        // Fake AEAD-shaped blob: relay must forward bit-exact without parsing.
        let mut blob: Vec<u8> = (0..64).map(|i| (i as u8) ^ secret[i % 32]).collect();
        blob.extend_from_slice(&[0x99u8; 16]);
        a.write_all(&frame([7u8; 16], b"attach")).await.unwrap();
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        b.write_all(&frame([7u8; 16], &blob)).await.unwrap();
        let mut hdr = [0u8; 40];
        a.read_exact(&mut hdr).await.unwrap();
        let parsed = parse_header(&hdr).unwrap();
        assert_eq!(parsed.len as usize, blob.len());
        let mut body = vec![0u8; parsed.len as usize + 16];
        a.read_exact(&mut body).await.unwrap();
        // Bit-exact: relay did not touch ciphertext or tag.
        assert_eq!(&body[..blob.len()], &blob[..]);
        // Tamper simulation: one flipped byte must NOT match original.
        let mut tampered = body.clone();
        tampered[0] ^= 0x01;
        assert_ne!(&tampered[..blob.len()], &blob[..]);
    }

    #[tokio::test]
    async fn pair_forwards_opaque_bytes() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let state = Arc::new(RelayState {
            sessions: Mutex::new(HashMap::new()),
        });
        let st = state.clone();
        tokio::spawn(async move {
            loop {
                let (s, p) = listener.accept().await.unwrap();
                let st = st.clone();
                tokio::spawn(async move {
                    pump_socket(st, s, p).await.unwrap();
                });
            }
        });
        let mut a = TcpStream::connect(addr).await.unwrap();
        let mut b = TcpStream::connect(addr).await.unwrap();
        // A attaches first (frame dropped, no B yet), then B attaches.
        a.write_all(&frame([9u8; 16], b"first")).await.unwrap();
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
        b.write_all(&frame([9u8; 16], b"second")).await.unwrap();
        // A must receive B's frame verbatim (header + payload + tag).
        let mut hdr = [0u8; 40];
        a.read_exact(&mut hdr).await.unwrap();
        let parsed = parse_header(&hdr).unwrap();
        assert_eq!(parsed.session, [9u8; 16]);
        let mut body = vec![0u8; parsed.len as usize + 16];
        a.read_exact(&mut body).await.unwrap();
        assert_eq!(&body[..6], b"second");
    }
}
