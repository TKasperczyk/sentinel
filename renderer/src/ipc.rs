use std::{
    env,
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
};

use log::{debug, warn};
use serde::Deserialize;

#[derive(Debug, Copy, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EntityState {
    Idle,
    Curious,
    Focused,
    Amused,
    Alert,
    Sleepy,
}

impl EntityState {
    pub fn as_u32(self) -> u32 {
        match self {
            EntityState::Idle => 0,
            EntityState::Curious => 1,
            EntityState::Focused => 2,
            EntityState::Amused => 3,
            EntityState::Alert => 4,
            EntityState::Sleepy => 5,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum IpcMessage {
    #[serde(rename = "state")]
    State { state: EntityState, intensity: f32 },
}

pub fn socket_candidates() -> Vec<PathBuf> {
    if let Ok(path) = env::var("SENTINEL_SOCKET_PATH") {
        if !path.trim().is_empty() {
            return vec![PathBuf::from(path)];
        }
    }

    let mut candidates = Vec::new();
    if let Ok(dir) = env::var("XDG_RUNTIME_DIR") {
        if !dir.trim().is_empty() {
            candidates.push(PathBuf::from(dir).join("sentinel.sock"));
        }
    }
    candidates.push(PathBuf::from("/tmp/sentinel.sock"));
    candidates
}

pub fn try_connect(candidates: &[PathBuf]) -> Option<(UnixStream, PathBuf)> {
    for path in candidates {
        match connect_one(path) {
            Ok(stream) => return Some((stream, path.clone())),
            Err(err) => debug!("IPC connect failed for {}: {err}", path.display()),
        }
    }
    None
}

fn connect_one(path: &Path) -> std::io::Result<UnixStream> {
    let stream = UnixStream::connect(path)?;
    stream.set_nonblocking(true)?;
    Ok(stream)
}

pub fn drain_messages(buffer: &mut Vec<u8>) -> Vec<IpcMessage> {
    const MAX_BUFFER_BYTES: usize = 1024 * 1024;
    if buffer.len() > MAX_BUFFER_BYTES {
        warn!("IPC buffer exceeded {MAX_BUFFER_BYTES} bytes; clearing");
        buffer.clear();
    }

    let mut out = Vec::new();
    loop {
        let newline = match buffer.iter().position(|b| *b == b'\n') {
            Some(idx) => idx,
            None => break,
        };

        let mut line = buffer.drain(..=newline).collect::<Vec<u8>>();
        if line.last() == Some(&b'\n') {
            line.pop();
        }
        if line.is_empty() {
            continue;
        }

        let line = match std::str::from_utf8(&line) {
            Ok(s) => s.trim(),
            Err(err) => {
                warn!("IPC message was not UTF-8: {err}");
                continue;
            }
        };
        if line.is_empty() {
            continue;
        }

        match serde_json::from_str::<IpcMessage>(line) {
            Ok(msg) => out.push(msg),
            Err(err) => warn!("IPC JSON parse failed: {err}; line={line:?}"),
        }
    }

    out
}
