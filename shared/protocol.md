# IPC Protocol

Communication between Observer and Renderer via Unix socket.

## Socket Path

`/tmp/sentinel.sock`

## Message Format

JSON messages, newline-delimited.

### State Update (Observer → Renderer)

```json
{
  "type": "state",
  "state": "idle",
  "intensity": 0.5,
  "timestamp": 1702000000000
}
```

**Fields:**
- `state`: One of `idle`, `curious`, `focused`, `amused`, `alert`, `sleepy`
- `intensity`: Float 0.0-1.0, how strongly the state is expressed
- `timestamp`: Unix timestamp in milliseconds

### Optional: Gaze Direction (Future)

```json
{
  "type": "gaze",
  "x": 0.3,
  "y": -0.2
}
```

Normalized coordinates where (0,0) is center, (-1,-1) is top-left, (1,1) is bottom-right.

## State Transitions

Renderer should smoothly interpolate between states over ~0.5-1.0 seconds.
