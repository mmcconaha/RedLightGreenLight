"use client";

import { useRef } from "react";
import { Status, STATUS_CYCLE } from "@/lib/types";
import { calendarWeeks } from "@/lib/dates";

export interface BlockDef {
  label: string;
  start_hour: number;
  end_hour: number;
}

// Presets used by the session-creation form.
export const SIMPLE_BLOCKS: BlockDef[] = [
  { label: "AM", start_hour: 6, end_hour: 12 },
  { label: "Mid", start_hour: 12, end_hour: 17 },
  { label: "PM", start_hour: 17, end_hour: 22 },
];
export const WHOLE_DAY_BLOCKS: BlockDef[] = [{ label: "Day", start_hour: 0, end_hour: 24 }];

const STATUS_COLOR: Record<Status, string> = {
  unset: "#2C2F38",
  green: "#35D07F",
  yellow: "#FFC24B",
  red: "#FF5A5F",
};

const WEEKDAY_LETTERS = ["S", "M", "T", "W", "T", "F", "S"];

export function cellKey(date: string, block: number) {
  return `${date}|${block}`;
}

function weekLabel(sunday: string): string {
  const d = new Date(sunday + "T00:00:00");
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function Hint() {
  return (
    <div className="mb-3 text-[11px] text-gray-500">
      Click a day to color it (green → yellow → red → clear). Keep holding and drag to paint that
      same color across more days.
    </div>
  );
}

export function InteractivePaintCalendar({
  startDate,
  endDate,
  dates,
  blocks,
  statuses,
  eventContext,
  onPaint,
  readOnly,
}: {
  startDate: string;
  endDate: string;
  dates: string[];
  blocks: BlockDef[];
  statuses: Record<string, Status>;
  eventContext?: Record<string, string[]>;
  onPaint: (date: string, block: number, value: Status) => void;
  readOnly?: boolean;
}) {
  const validDates = new Set(dates);
  const weeks = calendarWeeks(startDate, endDate);
  const paintingRef = useRef(false);
  const strokeValueRef = useRef<Status | null>(null);

  const startPaint = (date: string, block: number) => {
    const current = statuses[cellKey(date, block)] ?? "unset";
    const nextIndex = (STATUS_CYCLE.indexOf(current) + 1) % STATUS_CYCLE.length;
    const value = STATUS_CYCLE[nextIndex];
    strokeValueRef.current = value;
    paintingRef.current = true;
    onPaint(date, block, value);
  };
  const continuePaint = (date: string, block: number) => {
    if (!paintingRef.current || strokeValueRef.current === null) return;
    onPaint(date, block, strokeValueRef.current);
  };
  const stopPaint = () => {
    paintingRef.current = false;
    strokeValueRef.current = null;
  };

  return (
    <div
      onMouseUp={stopPaint}
      onMouseLeave={stopPaint}
      onTouchEnd={stopPaint}
      onTouchMove={(e) => {
        if (!paintingRef.current) return;
        const touch = e.touches[0];
        const el = document.elementFromPoint(touch.clientX, touch.clientY) as HTMLElement | null;
        const date = el?.getAttribute("data-date");
        const blockAttr = el?.getAttribute("data-block");
        if (date && blockAttr !== null && blockAttr !== undefined) continuePaint(date, Number(blockAttr));
      }}
    >
      <Hint />
      {weeks.map((week) => (
        <div key={week[0]} className="mb-5 bg-[#1A1B21] border border-[#2C2F38] rounded-xl p-3">
          <div className="text-[10px] uppercase tracking-wide text-gray-500 font-bold mb-1">
            Week of {weekLabel(week[0])}
          </div>
          <div className="grid gap-[3px]" style={{ gridTemplateColumns: "68px repeat(7, 1fr)" }}>
            <div />
            {week.map((date) => {
              const d = new Date(date + "T00:00:00");
              return (
                <div key={date} className="text-center text-[10px] text-gray-500 font-bold leading-tight">
                  {WEEKDAY_LETTERS[d.getDay()]}
                  <br />
                  {d.getDate()}
                </div>
              );
            })}
            {blocks.map((b, block) => (
              <div key={block} className="contents">
                <div className="text-[10px] text-gray-400 flex items-center font-bold leading-tight pr-1">{b.label}</div>
                {week.map((date) => {
                  if (!validDates.has(date)) {
                    return <div key={date} className="h-10" />;
                  }
                  const status = statuses[cellKey(date, block)] ?? "unset";
                  const notes = eventContext?.[cellKey(date, block)];
                  return (
                    <div
                      key={date}
                      data-date={date}
                      data-block={block}
                      onMouseDown={readOnly ? undefined : () => startPaint(date, block)}
                      onMouseEnter={readOnly ? undefined : () => continuePaint(date, block)}
                      onTouchStart={readOnly ? undefined : () => startPaint(date, block)}
                      title={notes?.join(", ")}
                      className="h-10 rounded border select-none flex items-center justify-center px-0.5"
                      style={{
                        borderColor: "#2C2F38",
                        background: STATUS_COLOR[status],
                        touchAction: readOnly ? "auto" : "none",
                        cursor: readOnly ? "default" : "pointer",
                      }}
                    >
                      {notes && notes.length > 0 && (
                        <span
                          className="text-[8px] font-bold leading-tight text-center truncate w-full"
                          style={{ color: "#0E1712" }}
                        >
                          {notes[0]}
                        </span>
                      )}
                    </div>
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

export function SummaryPaintCalendar({
  startDate,
  endDate,
  dates,
  blocks,
  counts,
  total,
}: {
  startDate: string;
  endDate: string;
  dates: string[];
  blocks: BlockDef[];
  counts: Record<string, { green: number; yellow: number; red: number }>;
  total: number;
}) {
  const validDates = new Set(dates);
  const weeks = calendarWeeks(startDate, endDate);
  const t = total || 1;

  return (
    <div>
      {weeks.map((week) => (
        <div key={week[0]} className="mb-5 bg-[#1A1B21] border border-[#2C2F38] rounded-xl p-3">
          <div className="text-[10px] uppercase tracking-wide text-gray-500 font-bold mb-1">
            Week of {weekLabel(week[0])}
          </div>
          <div className="grid gap-[3px]" style={{ gridTemplateColumns: "68px repeat(7, 1fr)" }}>
            <div />
            {week.map((date) => {
              const d = new Date(date + "T00:00:00");
              return (
                <div key={date} className="text-center text-[10px] text-gray-500 font-bold leading-tight">
                  {WEEKDAY_LETTERS[d.getDay()]}
                  <br />
                  {d.getDate()}
                </div>
              );
            })}
            {blocks.map((b, block) => (
              <div key={block} className="contents">
                <div className="text-[10px] text-gray-400 flex items-center font-bold leading-tight pr-1">{b.label}</div>
                {week.map((date) => {
                  if (!validDates.has(date)) {
                    return <div key={date} className="h-10" />;
                  }
                  const c = counts[cellKey(date, block)] ?? { green: 0, yellow: 0, red: 0 };
                  let bg = "#2C2F38";
                  if (c.red > 0) bg = `rgba(255,90,95,${0.25 + 0.5 * (c.red / t)})`;
                  else if (c.green === t && t > 0) bg = "#35D07F";
                  else if (c.green + c.yellow > 0) bg = `rgba(53,208,127,${0.2 + 0.6 * (c.green / t)})`;
                  return (
                    <div
                      key={date}
                      title={`${c.green} free, ${c.yellow} flexible, ${c.red} busy`}
                      className="h-10 rounded border"
                      style={{ borderColor: "#2C2F38", background: bg }}
                    />
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
