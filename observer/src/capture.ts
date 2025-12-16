function formatCommandError(stderr: Uint8Array): string {
  const text = new TextDecoder().decode(stderr).trim();
  return text.length > 0 ? text : "unknown error";
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
