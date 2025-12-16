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

  (async () => {
    for await (const conn of listener) {
      clients.add(conn);
      void handleClient(conn);
    }
  })();

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
      clients.delete(conn);
      try {
        conn.close();
      } catch {
        // Ignore.
      }
    }
  }

  return {
    broadcast(update: StateUpdate) {
      const payload = new TextEncoder().encode(`${JSON.stringify(update)}\n`);
      for (const conn of clients) {
        conn.write(payload).catch(() => {
          clients.delete(conn);
          try {
            conn.close();
          } catch {
            // Ignore.
          }
        });
      }
    },
    close() {
      try {
        listener.close();
      } finally {
        for (const conn of clients) {
          try {
            conn.close();
          } catch {
            // Ignore.
          }
        }
        clients.clear();
      }
    },
  };
}

export const startUnixSocketServer = createIpcServer;
