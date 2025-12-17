# Sentinel

An intelligent live wallpaper for Wayland that reacts to your screen content.

Sentinel has two parts:
- **Observer (Deno)**: captures the screen, asks a vision model for a lightweight classification, and emits an entity state over a Unix socket.
- **Renderer (Rust/wgpu)**: draws the reactive wallpaper (wlr-layer-shell background surface).

## Architecture

```
┌─────────────────────┐         ┌─────────────────────────────┐
│   Observer (Deno)   │         │    Renderer (Rust/wgpu)     │
├─────────────────────┤  Unix   ├─────────────────────────────┤
│ grim → VLM → state  │ Socket  │ wlr-layer-shell + ray march │
│                     │────────▶│ Abstract entity with eyes   │
│ Captures screen     │         │ Expression-driven animation │
│ Analyzes via LLM    │         │ Runs as background layer    │
│ Broadcasts state    │         │                             │
└─────────────────────┘         └─────────────────────────────┘
```

## Components

### Observer (`observer/`)
- Periodic screen capture via `grim`
- Vision LLM analysis via LM Studio local API
- State machine: screen content → mood → expression state
- Unix socket server broadcasting state updates

### Renderer (`renderer/`)
- wlr-layer-shell Wayland client (background layer)
- wgpu-based GPU rendering
- WGSL ray marching shader for abstract entity
- Unix socket client receiving state updates

## States

| State | Trigger | Visual |
|-------|---------|--------|
| `idle` | Low activity, desktop | Slow breathing, lazy drift |
| `curious` | New window, interesting content | Eyes widen, slight lean |
| `focused` | Code editor, terminal work | Concentrated gaze, still |
| `amused` | Memes, funny content | Playful movement |
| `alert` | Errors, warnings, red UI | Sharp attention, brightens |
| `sleepy` | Prolonged inactivity | Eyes droop, slow pulse |

## Requirements

- Wayland compositor with wlr-layer-shell (Hyprland, Sway, etc.)
- `grim` for screen capture
- A vision-capable VLM endpoint (OpenAI-compatible `POST /v1/chat/completions`, e.g. LM Studio)
- Rust toolchain
- Deno runtime

## Building

```bash
# Observer
cd observer && deno task build

# Renderer
cd renderer && cargo build --release
```

## Running

```bash
# Start observer
cd observer && deno task start

# Start renderer (as wallpaper)
../renderer/target/release/sentinel-renderer &
```

## Environment variables

Observer:
- `SENTINEL_SOCKET_PATH`: Unix socket path (default: `$XDG_RUNTIME_DIR/sentinel.sock` if writable, else `/tmp/sentinel.sock`)
- `SENTINEL_CAPTURE_INTERVAL`: capture interval in ms (default: `10000`)
- `SENTINEL_VLM_ENDPOINT`: VLM base URL (default: `http://localhost:1234/v1`)
- `SENTINEL_VLM_MODEL`: model name (default: `qwen2.5-vl-7b-instruct`)

Renderer:
- `SENTINEL_SOCKET_PATH`: Unix socket path (same behavior as observer)
- `SENTINEL_TRANSITION_DURATION`: state transition duration in seconds (default: `0.75`)
- `SENTINEL_ENTITY_STATE`: override initial state index `0-5` (default: `0`)
- `SENTINEL_ENTITY_INTENSITY`: override initial intensity `0.0-1.0` (default: `1.0`)
- `SENTINEL_ENTITY_CYCLE`: cycle states for debugging (`true`/`1`)

Logging:
- `RUST_LOG`: renderer log level (e.g. `info`, `debug`)

## License

MIT
