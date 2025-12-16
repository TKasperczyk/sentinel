# Sentinel

An intelligent live wallpaper for Wayland that reacts to your screen content.

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
- LM Studio with a vision model loaded
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
# Start renderer (as wallpaper)
./renderer/target/release/sentinel-renderer &

# Start observer
cd observer && deno task start
```

## License

MIT
