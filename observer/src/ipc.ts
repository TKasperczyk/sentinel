import type { StateUpdate } from "./state.ts";

export interface IpcServer {
  broadcast(update: StateUpdate): void;
  close(): void;
}

export async function createIpcServer(socketPath: string): Promise<IpcServer> {
  try {
    await Deno.remove(socketPath);
  } catch (err) {
    if (!(err instanceof Deno.errors.NotFound)) throw err;
  }

  const listener = Deno.listen({ transport: "unix", path: socketPath });
  const clients = new Set<Deno.Conn>();
  const writeChains = new Map<Deno.Conn, Promise<void>>();
  const encoder = new TextEncoder();
  let closing = false;

  (async () => {
    try {
      for await (const conn of listener) {
        clients.add(conn);
        void handleClient(conn);
      }
    } catch (err) {
      // Listener.close() will cause the accept loop to error; suppress noisy logs on shutdown.
      if (!closing) console.error("IPC listener error:", err);
    }
  })();

  async function writeAll(conn: Deno.Conn, data: Uint8Array): Promise<void> {
    let offset = 0;
    while (offset < data.length) {
      const written = await conn.write(data.subarray(offset));
      if (written === 0) {
        throw new Error("IPC client disconnected");
      }
      offset += written;
    }
  }

  function dropClient(conn: Deno.Conn): void {
    clients.delete(conn);
    writeChains.delete(conn);
    try {
      conn.close();
    } catch {
      // Ignore.
    }
  }

  async function handleClient(conn: Deno.Conn): Promise<void> {
    try {
      const buffer = new Uint8Array(1024);
      while (true) {
        const read = await conn.read(buffer);
        if (read === null) break;
      }
    } catch {
      // Ignore placeholder errors.
    } finally {
      dropClient(conn);
    }
  }

  return {
    broadcast(update: StateUpdate) {
      const payload = encoder.encode(`${JSON.stringify(update)}\n`);
      for (const conn of clients) {
        const prev = writeChains.get(conn) ?? Promise.resolve();
        const next = prev
          .then(() => writeAll(conn, payload))
          .catch(() => dropClient(conn));
        writeChains.set(conn, next);
      }
    },
    close() {
      closing = true;
      try {
        listener.close();
      } finally {
        for (const conn of clients) {
          dropClient(conn);
        }
        try {
          Deno.removeSync(socketPath);
        } catch (err) {
          if (!(err instanceof Deno.errors.NotFound)) throw err;
        }
      }
    },
  };
}

export const startUnixSocketServer = createIpcServer;
