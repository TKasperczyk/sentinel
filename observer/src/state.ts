export type EntityState = "idle" | "curious" | "focused" | "amused" | "alert" | "sleepy";

export interface StateUpdate {
  type: "state";
  state: EntityState;
  intensity: number;
  timestamp: number;
}

export interface ScreenAnalysis {
  mood: string;
  activity: string;
  confidence: number;
}

export interface StateMachine {
  getState(): EntityState;
  updateFromAnalysis(analysis: ScreenAnalysis): StateUpdate;
}

export function createStateMachine(initialState: EntityState = "idle"): StateMachine {
  let state: EntityState = initialState;

  return {
    getState: () => state,
    updateFromAnalysis: (analysis) => {
      const intensity = Math.max(0, Math.min(1, analysis.confidence));

      if (analysis.confidence >= 0.8) state = "focused";
      else if (analysis.confidence >= 0.4) state = "curious";
      else state = "idle";

      return {
        type: "state",
        state,
        intensity,
        timestamp: Date.now(),
      };
    },
  };
}
