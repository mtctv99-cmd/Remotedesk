use hbb_common::{bail, tls::TlsType, ResultType};
use serde_derive::{Deserialize, Serialize};

use super::deploy::{join_path, validate_server_url};
use crate::hbbs_http::{create_http_client_async, HbbHttpResponse};

/// A chat message sent to the AI assistant backend.
#[derive(Debug, PartialEq, Default, Serialize, Deserialize, Clone)]
pub struct ChatRequest {
    #[serde(default)]
    pub session_id: String,
    #[serde(default)]
    pub prompt: String,
}

/// The assistant reply for a [`ChatRequest`].
#[derive(Debug, PartialEq, Default, Serialize, Deserialize, Clone)]
pub struct ChatResponse {
    #[serde(default)]
    pub session_id: String,
    #[serde(default)]
    pub reply: String,
}

/// Send a chat request to the AI backend.
///
/// [Note]
/// Skeleton: the endpoint path is a placeholder and streaming is TODO.
/// Not wired into the flutter event stream (src/flutter.rs) yet.
pub async fn send_chat(server_url: &str, req: &ChatRequest) -> ResultType<ChatResponse> {
    // Keep the SSRF guard: an unset/loopback/private endpoint must not be
    // reachable through a chat URL even while this endpoint is a skeleton.
    let base = validate_server_url(server_url)?;
    // TODO: confirm the real endpoint path and auth headers with the backend.
    let url = join_path(&base, "api/deskagent/ai/chat");
    let client = create_http_client_async(TlsType::Rustls, false);
    let resp = client.post(&url).json(req).send().await?;
    let body = resp.text().await?;
    match HbbHttpResponse::<ChatResponse>::parse(&body)? {
        HbbHttpResponse::Data(data) => Ok(data),
        HbbHttpResponse::Error(e) => bail!("chat error: {}", e),
        HbbHttpResponse::ErrorFormat | HbbHttpResponse::DataTypeFormat => {
            bail!("unexpected chat response format")
        }
    }
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_chat_serde_roundtrip() {
        let resp = ChatResponse {
            session_id: "s1".to_owned(),
            reply: "hello".to_owned(),
        };
        let s = serde_json::to_string(&resp).unwrap();
        assert_eq!(serde_json::from_str::<ChatResponse>(&s).unwrap(), resp);
    }
}
