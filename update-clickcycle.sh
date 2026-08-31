#!/bin/bash
set -e
echo "Writing components/Calendar.tsx..."
cat > "components/Calendar.tsx" << 'CAL_EOF'
"use client";

import { useRef } from "react";
import { Status, STATUS_CYCLE } from "@/lib/types";
import { calendarWeeks } from "@/lib/dates";

const STATUS_COLOR: Record<Status, string> = {
  unset: "#2C2F38",
  green: "#35D07F",
  yellow: "#FFC24B",
  red: "#FF5A5F",
};

export const BLOCK_LABELS = ["AM", "Mid", "PM"];
export const BLOCK_FULL_LABELS = ["Morning", "Midday", "Evening"];
const WEEKDAY_LETTERS = ["S", "M", "T", "W", "T", "F", "S"];

export function cellKey(date: string, block: number) {
  return `${date}|${block}`;
}

function weekLabel(sunday: string): string {
  const d = new Date(sunday + "T00:00:00");
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function Legend() {
  return (
    <div className="flex gap-4 mb-1 text-[11px] text-gray-500">
      <span><span className="font-bold text-gray-400">AM</span> = morning</span>
      <span><span className="font-bold text-gray-400">Mid</span> = midday</span>
      <span><span className="font-bold text-gray-400">PM</span> = evening</span>
    </div>
  );
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
  statuses,
  onPaint,
}: {
  startDate: string;
  endDate: string;
  dates: string[];
  statuses: Record<string, Status>;
  onPaint: (date: string, block: number, value: Status) => void;
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
      <Legend />
      <Hint />
      {weeks.map((week) => (
        <div key={week[0]} className="mb-4">
          <div className="text-[10px] uppercase tracking-wide text-gray-500 font-bold mb-1">
            Week of {weekLabel(week[0])}
          </div>
          <div className="grid gap-[3px]" style={{ gridTemplateColumns: "30px repeat(7, 1fr)" }}>
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
            {BLOCK_LABELS.map((label, block) => (
              <div key={label} className="contents">
                <div className="text-[9px] text-gray-500 flex items-center font-bold">{label}</div>
                {week.map((date) => {
                  if (!validDates.has(date)) {
                    return <div key={date} className="h-7" />;
                  }
                  const status = statuses[cellKey(date, block)] ?? "unset";
                  return (
                    <div
                      key={date}
                      data-date={date}
                      data-block={block}
                      onMouseDown={() => startPaint(date, block)}
                      onMouseEnter={() => continuePaint(date, block)}
                      onTouchStart={() => startPaint(date, block)}
                      className="h-7 rounded border select-none"
                      style={{
                        borderColor: "#2C2F38",
                        background: STATUS_COLOR[status],
                        touchAction: "none",
                        cursor: "pointer",
                      }}
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

export function SummaryPaintCalendar({
  startDate,
  endDate,
  dates,
  counts,
  total,
}: {
  startDate: string;
  endDate: string;
  dates: string[];
  counts: Record<string, { green: number; yellow: number; red: number }>;
  total: number;
}) {
  const validDates = new Set(dates);
  const weeks = calendarWeeks(startDate, endDate);
  const t = total || 1;

  return (
    <div>
      <Legend />
      {weeks.map((week) => (
        <div key={week[0]} className="mb-4">
          <div className="text-[10px] uppercase tracking-wide text-gray-500 font-bold mb-1">
            Week of {weekLabel(week[0])}
          </div>
          <div className="grid gap-[3px]" style={{ gridTemplateColumns: "30px repeat(7, 1fr)" }}>
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
            {BLOCK_LABELS.map((label, block) => (
              <div key={label} className="contents">
                <div className="text-[9px] text-gray-500 flex items-center font-bold">{label}</div>
                {week.map((date) => {
                  if (!validDates.has(date)) {
                    return <div key={date} className="h-7" />;
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
                      className="h-7 rounded border"
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
CAL_EOF
echo "Writing respond page..."
cat > "app/session/[id]/respond/page.tsx" << 'RESPOND_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { Status } from "@/lib/types";
import { dateRange } from "@/lib/dates";
import { InteractivePaintCalendar, cellKey } from "@/components/Calendar";

export default function RespondPage({ params }: { params: { id: string } }) {
  const [checkingSession, setCheckingSession] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState("");

  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [dates, setDates] = useState<string[]>([]);
  const [statuses, setStatuses] = useState<Record<string, Status>>({});
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [loadError, setLoadError] = useState("");

  useEffect(() => {
    const load = async () => {
      const { data: session, error: sessionError } = await supabase
        .from("sessions")
        .select("start_date, end_date")
        .eq("id", params.id)
        .single();

      if (sessionError || !session?.start_date || !session?.end_date) {
        setLoadError(
          "This session doesn't have a date range set up yet — ask whoever's organizing to add one."
        );
        setCheckingSession(false);
        return;
      }

      setStartDate(session.start_date);
      setEndDate(session.end_date);
      setDates(dateRange(session.start_date, session.end_date));

      const { data } = await supabase.auth.getSession();
      if (data.session) {
        const { data: member } = await supabase
          .from("members")
          .select("id, name")
          .eq("user_id", data.session.user.id)
          .single();
        if (member) {
          setMemberId(member.id);
          setMemberName(member.name);
        }
      }
      setCheckingSession(false);
    };
    load();
  }, [params.id]);

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password, or ask whoever set this up.");
      return;
    }
    const { data: member } = await supabase
      .from("members")
      .select("id, name")
      .eq("user_id", data.user.id)
      .single();
    if (!member) {
      setLoginError("Logged in, but no member profile found for this band yet.");
      return;
    }
    setMemberId(member.id);
    setMemberName(member.name);
  };

  const handlePaint = (date: string, block: number, value: Status) => {
    setStatuses((prev) => ({ ...prev, [cellKey(date, block)]: value }));
  };

  const submit = async () => {
    if (!memberId) return;
    setSubmitting(true);

    const rows: any[] = [];
    dates.forEach((date, day_index) => {
      [0, 1, 2].forEach((block_index) => {
        const status = statuses[cellKey(date, block_index)];
        if (status && status !== "unset") {
          rows.push({
            session_id: params.id,
            member_id: memberId,
            day_index,
            block_index,
            status,
          });
        }
      });
    });

    if (rows.length > 0) {
      await supabase
        .from("availability")
        .upsert(rows, { onConflict: "session_id,member_id,day_index,block_index" });
    }

    setSubmitting(false);
    setSubmitted(true);
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <div className="flex gap-2 mb-2">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-3xl font-black uppercase tracking-tight leading-none mb-2">
          Red Light
          <br />
          Green Light
        </h1>
        <p className="text-sm text-gray-400 mb-5 max-w-md">
          Click a day to color it, drag to paint more. No calendar app, no explaining, no guilt.
        </p>

        <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3 text-sm text-gray-300 mb-6 flex gap-2">
          <span>🔒</span>
          <span>
            Nobody sees your reasons — only red, yellow, or green. Your answers stay private; the
            group only sees the combined light.
          </span>
        </div>

        {loadError ? (
          <p className="text-[#FF5A5F] text-sm">{loadError}</p>
        ) : checkingSession ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : !memberId ? (
          <div>
            <input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Email"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            <input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              placeholder="Password"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            {loginError && <p className="text-[#FF5A5F] text-xs mb-3">{loginError}</p>}
            <button
              onClick={login}
              className="w-full py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              Log in
            </button>
          </div>
        ) : submitted ? (
          <p className="text-[#35D07F] text-sm">
            Got it, {memberName} — thanks for not making this a whole thing.
          </p>
        ) : (
          <>
            <p className="text-sm text-gray-300 mb-3">Hey {memberName} —</p>

            <InteractivePaintCalendar
              startDate={startDate}
              endDate={endDate}
              dates={dates}
              statuses={statuses}
              onPaint={handlePaint}
            />

            <button
              onClick={submit}
              disabled={submitting}
              className="w-full mt-2 py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              {submitting ? "Sending…" : "Send my availability"}
            </button>
          </>
        )}
      </div>
    </main>
  );
}
RESPOND_EOF
echo "Done. (organizer page and lib/dates.ts are unchanged from the last update.)"
