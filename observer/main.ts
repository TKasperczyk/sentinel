import { captureScreen, pngDimensions } from "./src/capture.ts";
import { analyzeScreen } from "./src/vlm.ts";
import { createStateMachine } from "./src/state.ts";
import { createIpcServer } from "./src/ipc.ts";
import { config } from "./config.ts";

const abortController = new AbortController();
let running = true;

Deno.addSignalListener("SIGINT", () => {
  console.log("\nReceived SIGINT, shutting down...");
  running = false;
  abortController.abort();
});

Deno.addSignalListener("SIGTERM", () => {
  console.log("Received SIGTERM, shutting down...");
  running = false;
  abortController.abort();
});

async function main() {
  console.log("Sentinel Observer starting...");
  console.log(`  Capture interval: ${config.captureInterval}ms`);
  console.log(`  Socket path: ${config.socketPath}`);
  console.log(`  VLM endpoint: ${config.vlmEndpoint}`);
  console.log(`  VLM model: ${config.vlmModel}`);

  const stateMachine = createStateMachine();
  const ipc = await createIpcServer(config.socketPath);
  let loggedCaptureResolution = false;

  try {
    while (running) {
      try {
        const imageData = await captureScreen();
        if (!loggedCaptureResolution) {
          const dims = pngDimensions(imageData);
          if (dims) console.log(`  Capture resolution: ${dims.width}x${dims.height}`);
          else console.log("  Capture resolution: unknown");
          loggedCaptureResolution = true;
        }
        const analysis = await analyzeScreen(imageData);
        const stateUpdate = stateMachine.updateFromAnalysis(analysis);
        ipc.broadcast(stateUpdate);
        console.log(`State: ${stateUpdate.state} (intensity: ${stateUpdate.intensity.toFixed(2)})`);
      } catch (err) {
        console.error("Error in capture/analyze loop:", err);
        // Continue running, will retry next interval
      }

      // Interruptible sleep (clean up listener to avoid leaks)
      if (abortController.signal.aborted) break;

      try {
        await new Promise<void>((resolve, reject) => {
          const timeout = setTimeout(() => {
            abortController.signal.removeEventListener("abort", onAbort);
            resolve();
          }, config.captureInterval);

          function onAbort() {
            clearTimeout(timeout);
            reject(new Error("Aborted"));
          }

          abortController.signal.addEventListener("abort", onAbort, { once: true });
        });
      } catch {
        // Aborted, exit loop
        break;
      }
    }
  } finally {
    console.log("Cleaning up...");
    ipc.close();
  }
}

main().catch(console.error);
