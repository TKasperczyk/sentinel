mod ipc;
mod render;

use log::info;
use tokio::signal;

#[tokio::main]
async fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    info!("Sentinel Renderer starting");

    // Placeholder: In Phase 3 we'll set up the Wayland layer-shell surface
    // For now, just wait for shutdown signal

    tokio::select! {
        _ = signal::ctrl_c() => {
            info!("Received Ctrl+C, shutting down");
        }
        _ = render::placeholder_render_loop() => {
            info!("Render loop exited");
        }
    }

    info!("Sentinel Renderer stopped");
}
