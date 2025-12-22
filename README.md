# Sentinel

> **Early Development** - This project is experimental and under active development. APIs, visuals, and behavior may change significantly.

An intelligent live wallpaper for Wayland that reacts to your screen content.

Sentinel watches what you're doing and responds with an abstract particle swarm that shifts its behavior based on detected context - curious when you open something new, focused when you're coding, playful when you're browsing memes.

## Architecture

```
┌─────────────────────┐         ┌─────────────────────────────┐
│   Observer (Deno)   │         │    Renderer (Rust/wgpu)     │
├─────────────────────┤  Unix   ├─────────────────────────────┤
│ grim → VLM → state  │ Socket  │ wlr-layer-shell + GPU shader│
│                     │────────▶│ Particle swarm simulation   │
│ Captures screen     │         │ State-driven behavior       │
│ Analyzes via LLM    │         │ Runs as background layer    │
└─────────────────────┘         └─────────────────────────────┘
```

## Components

### Observer (`observer/`)
- Periodic screen capture via `grim`
- Vision LLM analysis via LM Studio local API
- State machine: screen content → mood → entity state
- Unix socket server broadcasting state updates

### Renderer (`renderer/`)
- wlr-layer-shell Wayland client (background layer)
- wgpu-based GPU rendering with ping-pong buffer simulation
- WGSL particle physics with FBM flow noise
- Motion blur trails and feedback effects
- Unix socket client receiving state updates

## States

| State | Trigger | Swarm Behavior |
|-------|---------|----------------|
| `idle` | Low activity, desktop | Gentle orbital drift, soft breathing |
| `curious` | New window, interesting content | Probing toward cursor, stretching |
| `focused` | Code editor, terminal work | Tight formation, dampened motion |
| `amused` | Memes, funny content | Random darting bursts |
| `alert` | Errors, warnings, red UI | Pulsing expansion, outward bursts |
| `sleepy` | Prolonged inactivity | Downward drift, minimal energy |

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
# Start observer (analyzes screen content)
cd observer && deno task start

# Start renderer (displays wallpaper)
./renderer/target/release/sentinel-renderer
```

## Environment Variables

### Observer
| Variable | Default | Description |
|----------|---------|-------------|
| `SENTINEL_SOCKET_PATH` | `$XDG_RUNTIME_DIR/sentinel.sock` | Unix socket path |
| `SENTINEL_CAPTURE_INTERVAL` | `10000` | Capture interval in ms |
| `SENTINEL_VLM_ENDPOINT` | `http://localhost:1234/v1` | VLM base URL |
| `SENTINEL_VLM_MODEL` | `qwen2.5-vl-7b-instruct` | Model name |

### Renderer
| Variable | Default | Description |
|----------|---------|-------------|
| `SENTINEL_SOCKET_PATH` | `$XDG_RUNTIME_DIR/sentinel.sock` | Unix socket path |
| `SENTINEL_TRANSITION_DURATION` | `0.75` | State transition duration (seconds) |
| `SENTINEL_ENTITY_STATE` | `0` | Override initial state (0-5) |
| `SENTINEL_ENTITY_INTENSITY` | `1.0` | Override intensity (0.0-1.0) |
| `SENTINEL_ENTITY_CYCLE` | `false` | Cycle states for debugging |
| `RUST_LOG` | - | Log level (`info`, `debug`) |

## License

MIT
