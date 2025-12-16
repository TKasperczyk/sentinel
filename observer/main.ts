import { captureScreen } from "./src/capture.ts";
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

  const stateMachine = createStateMachine();
  const ipc = await createIpcServer(config.socketPath);

  try {
    while (running) {
      try {
        const screenshotPath = await captureScreen();
        const analysis = await analyzeScreen(screenshotPath);
        const stateUpdate = stateMachine.updateFromAnalysis(analysis);
        ipc.broadcast(stateUpdate);
        console.log(`State: ${stateUpdate.state} (intensity: ${stateUpdate.intensity.toFixed(2)})`);
      } catch (err) {
        console.error("Error in capture/analyze loop:", err);
        // Continue running, will retry next interval
      }

      // Interruptible sleep
      try {
        await new Promise<void>((resolve, reject) => {
          const timeout = setTimeout(resolve, config.captureInterval);
          abortController.signal.addEventListener(
            "abort",
            () => {
              clearTimeout(timeout);
              reject(new Error("Aborted"));
            },
            { once: true },
          );
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
