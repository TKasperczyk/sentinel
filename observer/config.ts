function getSocketPath(): string {
  const envPath = Deno.env.get("SENTINEL_SOCKET_PATH");
  if (envPath) return envPath;

  const xdgRuntime = Deno.env.get("XDG_RUNTIME_DIR");
  if (xdgRuntime) {
    const probePath = `${xdgRuntime}/.sentinel-write-probe-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    try {
      const file = Deno.openSync(probePath, { createNew: true, write: true });
      file.close();
      Deno.removeSync(probePath);
      return `${xdgRuntime}/sentinel.sock`;
    } catch {
      console.warn(`XDG_RUNTIME_DIR not writable (${xdgRuntime}), falling back to /tmp/sentinel.sock`);
    }
  }

  return "/tmp/sentinel.sock";
}

function getInterval(): number {
  const env = Deno.env.get("SENTINEL_CAPTURE_INTERVAL");
  if (!env) return 10000;

  const parsed = Number(env);
  if (!Number.isFinite(parsed) || parsed < 1000) {
    console.warn(`Invalid SENTINEL_CAPTURE_INTERVAL: ${env}, using default 10000ms`);
    return 10000;
  }
  return parsed;
}

export const config = {
  captureInterval: getInterval(),
  socketPath: getSocketPath(),
  vlmEndpoint: Deno.env.get("SENTINEL_VLM_ENDPOINT") ?? "http://localhost:1234/v1",
  vlmModel: Deno.env.get("SENTINEL_VLM_MODEL") ?? "qwen2.5-vl-7b-instruct",
};
