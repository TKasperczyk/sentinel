import { config } from "../config.ts";
import type { Activity, Mood, ScreenAnalysis } from "./state.ts";

interface VlmResponse {
  activity: string;
  mood: string;
  hasErrors: boolean;
  confidence: number;
}

const PROMPT =
  `Analyze this screenshot and respond with ONLY a JSON object:\n` +
  `{\n` +
  `  "activity": "coding" | "browsing" | "media" | "chat" | "gaming" | "idle" | "error" | "other",\n` +
  `  "mood": "focused" | "relaxed" | "frustrated" | "entertained" | "neutral",\n` +
  `  "hasErrors": boolean,\n` +
  `  "confidence": 0.0-1.0\n` +
  `}\n\n` +
  `Look for: code editors, terminals, browsers, video players, games, error dialogs, red warning indicators.`;

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
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  return trimmed.slice(start, end + 1);
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
