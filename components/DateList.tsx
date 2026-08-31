"use client";

import { Status } from "@/lib/types";
import { formatFullDate, weekKey } from "@/lib/dates";

const STATUS_COLOR: Record<Status, string> = {
  unset: "#3A3D46",
  green: "#35D07F",
  yellow: "#FFC24B",
  red: "#FF5A5F",
};
const STATUS_LABEL: Record<Status, string> = {
  unset: "Tap to set",
  green: "Free",
  yellow: "Flexible",
  red: "Busy",
};

export function InteractiveDateList({
  dates,
  statuses,
  onToggle,
}: {
  dates: string[];
  statuses: Record<string, Status>;
  onToggle: (date: string) => void;
}) {
  let lastWeek = "";
  return (
    <div>
      {dates.map((date) => {
        const wk = weekKey(date);
        const showWeekHeader = wk !== lastWeek;
        lastWeek = wk;
        const status = statuses[date] ?? "unset";
        return (
          <div key={date}>
            {showWeekHeader && (
              <div className="text-xs uppercase tracking-wide text-gray-500 font-bold mt-4 mb-1.5">
                Week of {formatFullDate(wk)}
              </div>
            )}
            <button
              onClick={() => onToggle(date)}
              className="w-full flex items-center justify-between rounded-lg border px-3 py-2.5 mb-1.5"
              style={{ borderColor: "#2C2F38", background: "#1C1E24" }}
            >
              <span className="text-sm">{formatFullDate(date)}</span>
              <span
                className="text-xs font-bold px-2.5 py-1 rounded-full"
                style={{
                  background: STATUS_COLOR[status],
                  color: status === "unset" ? "#C7C9D1" : "#0E1712",
                  opacity: status === "unset" ? 0.5 : 1,
                }}
              >
                {STATUS_LABEL[status]}
              </span>
            </button>
          </div>
        );
      })}
    </div>
  );
}

export function SummaryDateList({
  dates,
  counts,
  total,
}: {
  dates: string[];
  counts: Record<string, { green: number; yellow: number; red: number }>;
  total: number;
}) {
  let lastWeek = "";
  return (
    <div>
      {dates.map((date) => {
        const wk = weekKey(date);
        const showWeekHeader = wk !== lastWeek;
        lastWeek = wk;
        const c = counts[date] ?? { green: 0, yellow: 0, red: 0 };
        const t = total || 1;
        let bg = "#2C2F38";
        if (c.red > 0) bg = `rgba(255,90,95,${0.25 + 0.5 * (c.red / t)})`;
        else if (c.green === t && t > 0) bg = STATUS_COLOR.green;
        else if (c.green + c.yellow > 0) bg = `rgba(53,208,127,${0.2 + 0.6 * (c.green / t)})`;
        return (
          <div key={date}>
            {showWeekHeader && (
              <div className="text-xs uppercase tracking-wide text-gray-500 font-bold mt-4 mb-1.5">
                Week of {formatFullDate(wk)}
              </div>
            )}
            <div
              title={`${c.green} free, ${c.yellow} flexible, ${c.red} busy`}
              className="w-full flex items-center justify-between rounded-lg border px-3 py-2.5 mb-1.5"
              style={{ borderColor: "#2C2F38", background: bg }}
            >
              <span className="text-sm">{formatFullDate(date)}</span>
              <span className="text-xs text-gray-300">
                {c.green}🟢 {c.yellow}🟡 {c.red}🔴
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
}
