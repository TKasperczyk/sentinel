function formatCommandError(stderr: Uint8Array): string {
  const text = new TextDecoder().decode(stderr).trim();
  return text.length > 0 ? text : "unknown error";
}

export function pngDimensions(data: Uint8Array): { width: number; height: number } | null {
  // PNG signature: 89 50 4E 47 0D 0A 1A 0A
  if (data.byteLength < 24) return null;
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let i = 0; i < sig.length; i++) {
    if (data[i] !== sig[i]) return null;
  }

  const type =
    String.fromCharCode(data[12], data[13], data[14], data[15]);
  if (type !== "IHDR") return null;

  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const width = view.getUint32(16, false);
  const height = view.getUint32(20, false);
  if (width <= 0 || height <= 0) return null;
  return { width, height };
}

async function runGrim(): Promise<Uint8Array> {
  const command = new Deno.Command("grim", {
    args: ["-t", "png", "-"],
    stdout: "piped",
    stderr: "piped",
  });

  const { success, stdout, stderr } = await command.output();
  if (!success) throw new Error(`grim failed: ${formatCommandError(stderr)}`);
  if (stdout.byteLength === 0) throw new Error("grim returned empty output");
  return stdout;
}

export async function captureScreen(): Promise<Uint8Array> {
  let lastError: unknown;

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      return await runGrim();
    } catch (err) {
      lastError = err;
      if (attempt === 0) await new Promise((r) => setTimeout(r, 100));
    }
  }

  if (lastError instanceof Deno.errors.NotFound) {
    throw new Error("grim not found in PATH");
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError));
}
