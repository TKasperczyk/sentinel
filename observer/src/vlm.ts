import type { ScreenAnalysis } from "./state.ts";

export async function analyzeScreen(imagePath: string): Promise<ScreenAnalysis> {
  void imagePath;

  return {
    mood: "neutral",
    activity: "unknown",
    confidence: 0,
  };
}
