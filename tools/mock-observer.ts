#!/usr/bin/env -S deno run -A
/**
 * Mock observer for testing renderer visuals.
 *
 * Controls:
 *   0-5  = Set entity state (idle/curious/focused/amused/alert/sleepy)
 *   +/-  = Adjust intensity
 *   c    = Cycle through states automatically
 *   q    = Quit
 */

const STATES = ["idle", "curious", "focused", "amused", "alert", "sleepy"] as const;
type EntityState = typeof STATES[number];

const socketPath = Deno.env.get("SENTINEL_SOCKET_PATH")
  ?? (Deno.env.get("XDG_RUNTIME_DIR") ? `${Deno.env.get("XDG_RUNTIME_DIR")}/sentinel.sock` : "/tmp/sentinel.sock");

// Remove existing socket if present
try { await Deno.remove(socketPath); } catch { /* ignore */ }

let currentState: EntityState = "idle";
let intensity = 0.5;
let cycling = false;
let cycleInterval: number | null = null;

const clients: Deno.Conn[] = [];

function broadcast() {
  const msg = JSON.stringify({
    type: "state",
    state: currentState,
    intensity,
    timestamp: Date.now(),
  }) + "\n";

  const data = new TextEncoder().encode(msg);
  for (const client of clients) {
    client.write(data).catch(() => {});
  }
}

function printStatus() {
  const stateIdx = STATES.indexOf(currentState);
  const bar = "█".repeat(Math.round(intensity * 20)) + "░".repeat(20 - Math.round(intensity * 20));
  console.clear();
  console.log("╔════════════════════════════════════════╗");
  console.log("║     SENTINEL MOCK OBSERVER             ║");
  console.log("╠════════════════════════════════════════╣");
  console.log(`║  State: [${stateIdx}] ${currentState.padEnd(10)}            ║`);
  console.log(`║  Intensity: ${bar} ${(intensity * 100).toFixed(0).padStart(3)}% ║`);
  console.log(`║  Cycling: ${cycling ? "ON " : "OFF"}                        ║`);
  console.log(`║  Clients: ${clients.length.toString().padEnd(3)}                        ║`);
  console.log("╠════════════════════════════════════════╣");
  console.log("║  Controls:                             ║");
  console.log("║    0-5 = Set state                     ║");
  console.log("║    +/- = Adjust intensity              ║");
  console.log("║    c   = Toggle auto-cycle             ║");
  console.log("║    q   = Quit                          ║");
  console.log("╚════════════════════════════════════════╝");
  console.log(`\nSocket: ${socketPath}`);
}

function toggleCycle() {
  cycling = !cycling;
  if (cycling) {
    let idx = STATES.indexOf(currentState);
    cycleInterval = setInterval(() => {
      idx = (idx + 1) % STATES.length;
      currentState = STATES[idx];
      broadcast();
      printStatus();
    }, 2000);
  } else if (cycleInterval) {
    clearInterval(cycleInterval);
    cycleInterval = null;
  }
}

// Start socket server
const listener = Deno.listen({ path: socketPath, transport: "unix" });
console.log(`Listening on ${socketPath}`);

// Accept clients in background
(async () => {
  for await (const conn of listener) {
    clients.push(conn);
    printStatus();
    // Send current state immediately
    const msg = JSON.stringify({ type: "state", state: currentState, intensity, timestamp: Date.now() }) + "\n";
    conn.write(new TextEncoder().encode(msg)).catch(() => {});
    // Clean up on close
    conn.readable.pipeTo(new WritableStream()).catch(() => {}).finally(() => {
      const idx = clients.indexOf(conn);
      if (idx >= 0) clients.splice(idx, 1);
      printStatus();
    });
  }
})();

// Handle keyboard input
Deno.stdin.setRaw(true);
printStatus();

const buf = new Uint8Array(1);
while (true) {
  const n = await Deno.stdin.read(buf);
  if (n === null) break;

  const key = String.fromCharCode(buf[0]);

  if (key === "q" || buf[0] === 3) { // q or Ctrl+C
    break;
  } else if (key >= "0" && key <= "5") {
    currentState = STATES[parseInt(key)];
    broadcast();
  } else if (key === "+" || key === "=") {
    intensity = Math.min(1, intensity + 0.1);
    broadcast();
  } else if (key === "-" || key === "_") {
    intensity = Math.max(0, intensity - 0.1);
    broadcast();
  } else if (key === "c") {
    toggleCycle();
  }

  printStatus();
}

// Cleanup
Deno.stdin.setRaw(false);
if (cycleInterval) clearInterval(cycleInterval);
listener.close();
try { await Deno.remove(socketPath); } catch { /* ignore */ }
console.log("\nBye!");
