use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateUpdate {
  pub r#type: String,
  pub state: String,
  pub intensity: f32,
  pub timestamp: u64,
}

pub async fn placeholder_ipc_loop() {
  // Placeholder for a Unix-socket IPC client.
}
