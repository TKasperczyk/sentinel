import { config } from "../config.ts";
import type { Activity, Mood, ScreenAnalysis } from "./state.ts";

interface VlmResponse {
  activity: string;
  mood: string;
  hasErrors: boolean;
  confidence: number;
}

const PROMPT =
  `
Analyze this screenshot and respond with ONLY a JSON object (no markdown, no extra keys).

Schema:
{
  "activity": "coding" | "browsing" | "media" | "chat" | "gaming" | "idle" | "error" | "other",
  "mood": "focused" | "relaxed" | "frustrated" | "entertained" | "neutral",
  "hasErrors": boolean,
  "confidence": 0.0-1.0
}

Classification rules:
- Pick the PRIMARY activity based on the foreground app.
- "coding": IDE/editor (VS Code/JetBrains/vim), terminal with dev commands/logs, diffs, build output.
- "browsing": web pages/docs/search, even if code snippets are visible.
- "chat": messaging apps/web chat with conversation threads.
- "media": video/audio player UI (timeline/play controls) or streaming content.
- "gaming": game viewport/HUD/menus.
- "idle": lock screen, wallpaper, blank desktop/no active content.
- "error": only when the SCREEN IS DOMINATED by an error/failure screen (crash dialog, BSOD-like screen, blocking error modal, full stack trace page).

Error detection (reduce false positives):
- Set "hasErrors": true ONLY for explicit errors: visible words like "error", "failed", "exception", "traceback", "panic", or a clear crash/error dialog.
- Do NOT treat red syntax highlighting, git diff colors, warning icons, or a single red underline as an error by itself.
- If there is an error while still clearly coding/browsing, keep "activity" as that task and set "hasErrors": true.

Mood guidance:
- focused: coding, reading docs, work dashboards.
- relaxed: casual browsing, music, calm desktop.
- entertained: videos, games, memes.
- frustrated: prominent errors/failures or crash dialogs.
- neutral: idle/ambiguous.

Few-shot examples (descriptions → JSON):
1) "VS Code with source code, terminal shows tests passing" →
{"activity":"coding","mood":"focused","hasErrors":false,"confidence":0.85}
2) "Browser reading documentation with code snippets" →
{"activity":"browsing","mood":"focused","hasErrors":false,"confidence":0.75}
3) "Chat app with conversation thread" →
{"activity":"chat","mood":"relaxed","hasErrors":false,"confidence":0.80}
4) "Video player with playback controls" →
{"activity":"media","mood":"entertained","hasErrors":false,"confidence":0.85}
5) "Game with HUD/minimap" →
{"activity":"gaming","mood":"entertained","hasErrors":false,"confidence":0.85}
6) "Terminal shows compilation error output" →
{"activity":"coding","mood":"frustrated","hasErrors":true,"confidence":0.80}
7) "Crash dialog or full-screen error screen" →
{"activity":"error","mood":"frustrated","hasErrors":true,"confidence":0.85}

If unsure, use "activity":"other" and set confidence ≤ 0.4.
`.trim();

function clamp01(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

function toBase64(data: Uint8Array): string {
  const chunkSize = 0x8000;
  const parts: string[] = [];
  for (let i = 0; i < data.length; i += chunkSize) {
    parts.push(String.fromCharCode(...data.subarray(i, i + chunkSize)));
  }
  return btoa(parts.join(""));
}

function chatCompletionsUrl(endpoint: string): string {
  const trimmed = endpoint.replace(/\/+$/, "");
  if (trimmed.endsWith("/chat/completions")) return trimmed;
  if (trimmed.endsWith("/v1")) return `${trimmed}/chat/completions`;
  return `${trimmed}/v1/chat/completions`;
}

function extractJson(text: string): string | null {
  const trimmed = text.trim();

  for (let i = 0; i < trimmed.length; i++) {
    if (trimmed[i] !== "{") continue;

    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let j = i; j < trimmed.length; j++) {
      const ch = trimmed[j];

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch === "\\") {
          escaped = true;
          continue;
        }
        if (ch === "\"") {
          inString = false;
        }
        continue;
      }

      if (ch === "\"") {
        inString = true;
        continue;
      }
      if (ch === "{") depth++;
      if (ch === "}") depth--;

      if (depth === 0) {
        const candidate = trimmed.slice(i, j + 1);
        try {
          JSON.parse(candidate);
          return candidate;
        } catch {
          break;
        }
      }
    }
  }

  return null;
}

function normalizeActivity(value: unknown): Activity {
  const raw = typeof value === "string" ? value.trim().toLowerCase() : "";
  switch (raw) {
    case "coding":
    case "browsing":
    case "media":
    case "chat":
    case "gaming":
    case "idle":
    case "error":
    case "other":
      return raw;
    default:
      return "other";
  }
}

function normalizeMood(value: unknown): Mood {
  const raw = typeof value === "string" ? value.trim().toLowerCase() : "";
  switch (raw) {
    case "focused":
    case "relaxed":
    case "frustrated":
    case "entertained":
    case "neutral":
      return raw;
    default:
      return "neutral";
  }
}

function normalizeHasErrors(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value.trim().toLowerCase() === "true";
  return Boolean(value);
}

function normalizeConfidence(value: unknown): number {
  if (typeof value === "number") return clamp01(value);
  const parsed = Number(value);
  return clamp01(parsed);
}

function errorAnalysis(): ScreenAnalysis {
  return { activity: "error", mood: "neutral", hasErrors: true, confidence: 0 };
}

export async function analyzeScreen(imageData: Uint8Array): Promise<ScreenAnalysis> {
  try {
    const base64 = toBase64(imageData);
    const url = chatCompletionsUrl(config.vlmEndpoint);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30_000);

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: config.vlmModel,
          messages: [
            {
              role: "user",
              content: [
                { type: "text", text: PROMPT },
                {
                  type: "image_url",
                  image_url: { url: `data:image/png;base64,${base64}` },
                },
              ],
            },
          ],
          temperature: 0,
          max_tokens: 256,
          stream: false,
        }),
        signal: controller.signal,
      });

      if (!response.ok) {
        const body = await response.text().catch(() => "");
        console.error(`VLM request failed (${response.status}): ${body || response.statusText}`);
        return errorAnalysis();
      }

      const payload = await response.json().catch(() => null) as {
        choices?: Array<{ message?: { content?: unknown } }>;
      } | null;

      const content = payload?.choices?.[0]?.message?.content;
      if (typeof content !== "string") {
        console.error("VLM response missing assistant content");
        return errorAnalysis();
      }

      const jsonText = extractJson(content);
      if (!jsonText) {
        console.error("VLM response did not contain a JSON object");
        return errorAnalysis();
      }

      const parsed = JSON.parse(jsonText) as Partial<VlmResponse>;
      return {
        activity: normalizeActivity(parsed.activity),
        mood: normalizeMood(parsed.mood),
        hasErrors: normalizeHasErrors(parsed.hasErrors),
        confidence: normalizeConfidence(parsed.confidence),
      };
    } finally {
      clearTimeout(timeout);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`VLM analyze failed: ${message}`);
    return errorAnalysis();
  }
}
