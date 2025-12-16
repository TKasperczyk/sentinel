export type EntityState = "idle" | "curious" | "focused" | "amused" | "alert" | "sleepy";

export type Activity = "coding" | "browsing" | "media" | "chat" | "gaming" | "idle" | "error" | "other";
export type Mood = "focused" | "relaxed" | "frustrated" | "entertained" | "neutral";

export interface StateUpdate {
  type: "state";
  state: EntityState;
  intensity: number;
  timestamp: number;
}

export interface ScreenAnalysis {
  activity: Activity;
  mood: Mood;
  hasErrors: boolean;
  confidence: number;
}

export interface StateMachine {
  getState(): EntityState;
  updateFromAnalysis(analysis: ScreenAnalysis): StateUpdate;
}

export function createStateMachine(initialState: EntityState = "idle"): StateMachine {
  let state: EntityState = initialState;
  let pendingState: EntityState | null = null;
  let pendingCycles = 0;
  let idleSince: number | null = null;

  const SLEEPY_AFTER_MS = 60_000;

  function mapToEntityState(analysis: ScreenAnalysis, now: number): EntityState {
    if (analysis.activity === "idle") {
      idleSince ??= now;
    } else {
      idleSince = null;
    }

    // hasErrors → "alert"
    if (analysis.hasErrors) return "alert";

    // activity=coding + mood=frustrated → "alert"
    if (analysis.activity === "coding" && analysis.mood === "frustrated") return "alert";

    // activity=coding/error + mood=focused → "focused"
    if ((analysis.activity === "coding" || analysis.activity === "error") && analysis.mood === "focused") return "focused";

    // activity=media/gaming + mood=entertained → "amused"
    if ((analysis.activity === "media" || analysis.activity === "gaming") && analysis.mood === "entertained") return "amused";

    // activity=idle → "sleepy" (after threshold) or "idle"
    if (analysis.activity === "idle") {
      const idleFor = idleSince ? now - idleSince : 0;
      return idleFor >= SLEEPY_AFTER_MS ? "sleepy" : "idle";
    }

    // activity=browsing/chat → "curious"
    if (analysis.activity === "browsing" || analysis.activity === "chat") return "curious";

    // default → "idle"
    return "idle";
  }

  return {
    getState: () => state,
    updateFromAnalysis: (analysis) => {
      const now = Date.now();
      const confidence = Number.isFinite(analysis.confidence) ? analysis.confidence : 0;
      const intensity = Math.max(0, Math.min(1, confidence));
      const target = mapToEntityState(analysis, now);

      // Anti-jitter: require state to be consistent for 2 cycles before changing.
      if (target === state) {
        pendingState = null;
        pendingCycles = 0;
      } else {
        if (pendingState === target) pendingCycles += 1;
        else {
          pendingState = target;
          pendingCycles = 1;
        }

        if (pendingCycles >= 2) {
          state = target;
          pendingState = null;
          pendingCycles = 0;
        }
      }

      return {
        type: "state",
        state,
        intensity,
        timestamp: now,
      };
    },
  };
}
