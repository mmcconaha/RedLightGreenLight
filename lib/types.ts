export type Status = "unset" | "green" | "yellow" | "red";

export const STATUS_CYCLE: Status[] = ["unset", "green", "yellow", "red"];

export const DEFAULT_DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
export const DEFAULT_BLOCKS = ["Morning", "Afternoon", "Evening"];

export interface CellCounts {
  day_index: number;
  block_index: number;
  green: number;
  yellow: number;
  red: number;
  responded: number;
}

export interface SuggestedWindow {
  day_index: number;
  block_index: number;
  score: number;
  counts: CellCounts;
}
