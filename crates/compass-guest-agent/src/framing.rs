use anyhow::{anyhow, bail, Result};
use serde::{de::DeserializeOwned, Serialize};

pub const MAX_FRAME_BYTE_COUNT: usize = 1536 * 1024 * 1024;

pub fn encode<T: Serialize>(value: &T) -> Result<Vec<u8>> {
    let body = serde_json::to_vec(value)?;
    if body.len() > MAX_FRAME_BYTE_COUNT {
        bail!(
            "frame exceeds max byte count: actual={} max={}",
            body.len(),
            MAX_FRAME_BYTE_COUNT
        );
    }
    let mut frame = Vec::with_capacity(4 + body.len());
    frame.extend_from_slice(&(body.len() as u32).to_be_bytes());
    frame.extend_from_slice(&body);
    Ok(frame)
}

pub fn decode<T: DeserializeOwned>(frame: &[u8]) -> Result<T> {
    if frame.len() < 4 {
        bail!("length header too short");
    }
    let declared = u32::from_be_bytes(frame[0..4].try_into().unwrap()) as usize;
    if declared > MAX_FRAME_BYTE_COUNT {
        bail!(
            "frame exceeds max byte count: actual={} max={}",
            declared,
            MAX_FRAME_BYTE_COUNT
        );
    }
    let body = frame
        .get(4..4 + declared)
        .ok_or_else(|| anyhow!("body shorter than declared length"))?;
    Ok(serde_json::from_slice(body)?)
}
