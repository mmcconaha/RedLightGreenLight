import { CellCounts, SuggestedWindow } from "./types";

/**
 * Scores a time block from aggregate counts only — no identity data,
 * no reasons, nothing beyond how many people are green/yellow/red.
 *
 *   score = (green x 2) + yellow - (red x 3) - (unset x 0.5)
 *
 * Blocks with any red are filtered out entirely: this tool is for
 * finding windows that work for everyone, not for outvoting someone.
 */
export function scoreCell(c: CellCounts): number {
  const unset = Math.max(c.responded - c.green - c.yellow - c.red, 0);
  return c.green * 2 + c.yellow - c.red * 3 - unset * 0.5;
}

export function topSuggestions(cells: CellCounts[], limit = 3): SuggestedWindow[] {
  return cells
    .filter((c) => c.red === 0 && c.green + c.yellow > 0)
    .map((c) => ({
      day_index: c.day_index,
      block_index: c.block_index,
      score: scoreCell(c),
      counts: c,
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);
}

/** Plain-language line, used as a fallback when the LLM blurb call is skipped. */
export function plainLine(c: CellCounts): string {
  if (c.red === 0 && c.yellow === 0) return `Everyone's clear — all ${c.green} lit green.`;
  if (c.yellow > 0 && c.red === 0)
    return `${c.green} free, ${c.yellow} flexible. Worth a quick check with them.`;
  return "Mostly open.";
}
