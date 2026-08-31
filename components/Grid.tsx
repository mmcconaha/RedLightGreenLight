"use client";

import { Status } from "@/lib/types";

const STATUS_COLOR: Record<Status, string> = {
  unset: "#3A3D46",
  green: "#35D07F",
  yellow: "#FFC24B",
  red: "#FF5A5F",
};

export function InteractiveGrid({
  days,
  blocks,
  grid,
  onCellClick,
}: {
  days: string[];
  blocks: string[];
  grid: Record<string, Status>;
  onCellClick: (key: string) => void;
}) {
  return (
    <div className="overflow-x-auto">
      <div style={{ minWidth: 460 }}>
        <HeaderRow days={days} />
        {blocks.map((block, b) => (
          <div
            key={block}
            className="grid gap-1 mb-1"
            style={{ gridTemplateColumns: `70px repeat(${days.length}, 1fr)` }}
          >
            <div className="text-xs text-gray-400 flex items-center">{block}</div>
            {days.map((_, d) => {
              const key = `${d}-${b}`;
              const status = grid[key] ?? "unset";
              return (
                <button
                  key={key}
                  onClick={() => onCellClick(key)}
                  title={status}
                  className="h-10 rounded-lg border"
                  style={{
                    borderColor: "#2C2F38",
                    background: STATUS_COLOR[status],
                    opacity: status === "unset" ? 0.6 : 1,
                  }}
                />
              );
            })}
          </div>
        ))}
        <Legend />
      </div>
    </div>
  );
}

export function SummaryGrid({
  days,
  blocks,
  cells,
  total,
}: {
  days: string[];
  blocks: string[];
  cells: Record<string, { green: number; yellow: number; red: number }>;
  total: number;
}) {
  return (
    <div className="overflow-x-auto">
      <div style={{ minWidth: 460 }}>
        <HeaderRow days={days} />
        {blocks.map((block, b) => (
          <div
            key={block}
            className="grid gap-1 mb-1"
            style={{ gridTemplateColumns: `70px repeat(${days.length}, 1fr)` }}
          >
            <div className="text-xs text-gray-400 flex items-center">{block}</div>
            {days.map((_, d) => {
              const key = `${d}-${b}`;
              const c = cells[key] ?? { green: 0, yellow: 0, red: 0 };
              const t = total || 1;
              let bg = "#2C2F38";
              if (c.red > 0) bg = `rgba(255,90,95,${0.25 + 0.5 * (c.red / t)})`;
              else if (c.green === t && t > 0) bg = STATUS_COLOR.green;
              else if (c.green + c.yellow > 0) bg = `rgba(53,208,127,${0.2 + 0.6 * (c.green / t)})`;
              return (
                <div
                  key={key}
                  title={`${c.green} free · ${c.yellow} flexible · ${c.red} busy`}
                  className="h-10 rounded-lg border"
                  style={{ borderColor: "#2C2F38", background: bg }}
                />
              );
            })}
          </div>
        ))}
        <Legend />
      </div>
    </div>
  );
}

function HeaderRow({ days }: { days: string[] }) {
  return (
    <div className="grid gap-1 mb-1" style={{ gridTemplateColumns: `70px repeat(${days.length}, 1fr)` }}>
      <div />
      {days.map((d) => (
        <div key={d} className="text-center text-xs font-bold text-gray-400">
          {d}
        </div>
      ))}
    </div>
  );
}

function Legend() {
  return (
    <div className="flex gap-4 mt-2 text-xs text-gray-400">
      {(["green", "yellow", "red"] as Status[]).map((s) => (
        <div key={s} className="flex items-center gap-1">
          <div className="w-2 h-2 rounded-full" style={{ background: STATUS_COLOR[s] }} />
          {s === "green" ? "Free" : s === "yellow" ? "Flexible" : "Busy"}
        </div>
      ))}
    </div>
  );
}
