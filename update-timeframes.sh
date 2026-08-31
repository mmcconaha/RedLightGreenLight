#!/bin/bash
set -e
echo "Writing lib/dates.ts..."
cat > "lib/dates.ts" << 'DATES_EOF'
export function dateRange(startISO: string, endISO: string): string[] {
  const dates: string[] = [];
  const start = new Date(startISO + "T00:00:00");
  const end = new Date(endISO + "T00:00:00");
  const cur = new Date(start);
  while (cur <= end) {
    dates.push(cur.toISOString().slice(0, 10));
    cur.setDate(cur.getDate() + 1);
  }
  return dates;
}

export function formatFullDate(dateISO: string): string {
  const d = new Date(dateISO + "T00:00:00");
  return d.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" });
}

export function weekKey(dateISO: string): string {
  const d = new Date(dateISO + "T00:00:00");
  const day = d.getDay();
  const diffToMonday = (day + 6) % 7;
  const monday = new Date(d);
  monday.setDate(d.getDate() - diffToMonday);
  return monday.toISOString().slice(0, 10);
}

// Returns a Sun-Sat grid of ISO date strings for a given month (0-indexed month),
// with null for padding cells before day 1 / after the last day.
export function monthGrid(year: number, month: number): (string | null)[][] {
  const firstDay = new Date(year, month, 1);
  const startWeekday = firstDay.getDay();
  const numDays = new Date(year, month + 1, 0).getDate();
  const cells: (string | null)[] = [];
  for (let i = 0; i < startWeekday; i++) cells.push(null);
  for (let d = 1; d <= numDays; d++) {
    const iso = `${year}-${String(month + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
    cells.push(iso);
  }
  while (cells.length % 7 !== 0) cells.push(null);
  const weeks: (string | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return weeks;
}

// Distinct year/month pairs spanned by a list of ISO dates, in order.
export function monthsInRange(dates: string[]): { year: number; month: number; label: string }[] {
  const seen = new Set<string>();
  const result: { year: number; month: number; label: string }[] = [];
  dates.forEach((iso) => {
    const [y, m] = iso.split("-").map(Number);
    const key = `${y}-${m}`;
    if (!seen.has(key)) {
      seen.add(key);
      const label = new Date(y, m - 1, 1).toLocaleDateString("en-US", {
        month: "long",
        year: "numeric",
      });
      result.push({ year: y, month: m - 1, label });
    }
  });
  return result;
}

// Full calendar weeks (Sun-Sat) covering the date range, including padding
// days from adjacent months so every week is a complete row of 7.
export function calendarWeeks(startISO: string, endISO: string): string[][] {
  const start = new Date(startISO + "T00:00:00");
  const end = new Date(endISO + "T00:00:00");
  const firstSunday = new Date(start);
  firstSunday.setDate(start.getDate() - start.getDay());
  const lastSaturday = new Date(end);
  lastSaturday.setDate(end.getDate() + (6 - end.getDay()));

  const weeks: string[][] = [];
  const cur = new Date(firstSunday);
  while (cur <= lastSaturday) {
    const week: string[] = [];
    for (let i = 0; i < 7; i++) {
      week.push(cur.toISOString().slice(0, 10));
      cur.setDate(cur.getDate() + 1);
    }
    weeks.push(week);
  }
  return weeks;
}

// Same as dateRange, but only includes dates whose weekday (0=Sun..6=Sat)
// is in activeWeekdays — lets an organizer exclude whole days of the week.
export function dateRangeFiltered(
  startISO: string,
  endISO: string,
  activeWeekdays: number[]
): string[] {
  return dateRange(startISO, endISO).filter((d) =>
    activeWeekdays.includes(new Date(d + "T00:00:00").getDay())
  );
}
DATES_EOF
echo "Writing lib/google.ts..."
cat > "lib/google.ts" << 'GOOGLE_EOF'
const CLIENT_ID = process.env.GOOGLE_CLIENT_ID!;
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET!;
const REDIRECT_URI = process.env.GOOGLE_REDIRECT_URI!;

export function googleAuthUrl(state: string): string {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    response_type: "code",
    scope: "https://www.googleapis.com/auth/calendar.events.readonly",
    access_type: "online",
    prompt: "consent",
    state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

export async function exchangeCode(code: string): Promise<string> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: REDIRECT_URI,
      grant_type: "authorization_code",
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(json.error_description || "Token exchange failed");
  return json.access_token as string;
}

export interface CalEvent {
  title: string;
  start: string;
  end: string;
}

export async function fetchEvents(
  accessToken: string,
  timeMinISO: string,
  timeMaxISO: string,
  timeZone: string
): Promise<CalEvent[]> {
  const params = new URLSearchParams({
    timeMin: timeMinISO,
    timeMax: timeMaxISO,
    timeZone,
    singleEvents: "true",
    orderBy: "startTime",
    maxResults: "2500",
  });
  const res = await fetch(
    `https://www.googleapis.com/calendar/v3/calendars/primary/events?${params.toString()}`,
    { headers: { authorization: `Bearer ${accessToken}` } }
  );
  const json = await res.json();
  if (json.error) {
    throw new Error(`events error: ${json.error.message || JSON.stringify(json.error)}`);
  }
  const items = json.items ?? [];
  return items
    .filter((e: any) => e.status !== "cancelled" && e.transparency !== "transparent")
    .filter((e: any) => e.start?.dateTime && e.end?.dateTime)
    .map((e: any) => ({
      title: e.summary || "(untitled event)",
      start: e.start.dateTime,
      end: e.end.dateTime,
    }));
}

function zonedTimeToUtc(dateISO: string, hour: number, timeZone: string): Date {
  let d = dateISO;
  let h = hour;
  if (h >= 24) {
    const next = new Date(dateISO + "T00:00:00Z");
    next.setUTCDate(next.getUTCDate() + 1);
    d = next.toISOString().slice(0, 10);
    h = h - 24;
  }
  const naiveUtc = new Date(`${d}T${String(h).padStart(2, "0")}:00:00Z`);
  const asIfLocal = new Date(naiveUtc.toLocaleString("en-US", { timeZone }));
  const asIfUtc = new Date(naiveUtc.toLocaleString("en-US", { timeZone: "UTC" }));
  const offset = asIfUtc.getTime() - asIfLocal.getTime();
  return new Date(naiveUtc.getTime() + offset);
}

/** Titles of events overlapping this custom hour range — empty array if none. */
export function eventsForRange(
  dateISO: string,
  startHour: number,
  endHour: number,
  timeZone: string,
  events: CalEvent[]
): string[] {
  const blockStart = zonedTimeToUtc(dateISO, startHour, timeZone);
  const blockEnd = zonedTimeToUtc(dateISO, endHour, timeZone);
  return events
    .filter((e) => new Date(e.start) < blockEnd && new Date(e.end) > blockStart)
    .map((e) => e.title);
}
GOOGLE_EOF
echo "Writing components/Calendar.tsx..."
cat > "components/Calendar.tsx" << 'CAL_EOF'
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
}: {
  startDate: string;
  endDate: string;
  dates: string[];
  blocks: BlockDef[];
  statuses: Record<string, Status>;
  eventContext?: Record<string, string[]>;
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
            {blocks.map((b, block) => (
              <div key={block} className="contents">
                <div className="text-[9px] text-gray-500 flex items-center font-bold truncate">{b.label}</div>
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
                      onMouseDown={() => startPaint(date, block)}
                      onMouseEnter={() => continuePaint(date, block)}
                      onTouchStart={() => startPaint(date, block)}
                      title={notes?.join(", ")}
                      className="h-10 rounded border select-none flex items-center justify-center px-0.5"
                      style={{
                        borderColor: "#2C2F38",
                        background: STATUS_COLOR[status],
                        touchAction: "none",
                        cursor: "pointer",
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
            {blocks.map((b, block) => (
              <div key={block} className="contents">
                <div className="text-[9px] text-gray-500 flex items-center font-bold truncate">{b.label}</div>
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
CAL_EOF
echo "Writing respond page..."
cat > "app/session/[id]/respond/page.tsx" << 'RESPOND_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { Status } from "@/lib/types";
import { dateRangeFiltered } from "@/lib/dates";
import { InteractivePaintCalendar, BlockDef, cellKey } from "@/components/Calendar";

export default function RespondPage({ params }: { params: { id: string } }) {
  const [checkingSession, setCheckingSession] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState("");

  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [blocks, setBlocks] = useState<BlockDef[]>([]);
  const [dates, setDates] = useState<string[]>([]);
  const [statuses, setStatuses] = useState<Record<string, Status>>({});
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [justSynced, setJustSynced] = useState<string | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [eventContext, setEventContext] = useState<Record<string, string[]>>({});

  const loadExisting = async (memberIdArg: string, dateList: string[]) => {
    const { data: existing } = await supabase
      .from("availability")
      .select("day_index, block_index, status")
      .eq("session_id", params.id)
      .eq("member_id", memberIdArg);
    if (existing && existing.length > 0) {
      const pre: Record<string, Status> = {};
      existing.forEach((r) => {
        const date = dateList[r.day_index];
        if (date) pre[cellKey(date, r.block_index)] = r.status as Status;
      });
      setStatuses(pre);
    }
  };

  useEffect(() => {
    const load = async () => {
      const { data: session, error: sessionError } = await supabase
        .from("sessions")
        .select("start_date, end_date, blocks, active_weekdays")
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
      const sessionBlocks: BlockDef[] = session.blocks ?? [];
      setBlocks(sessionBlocks);
      const activeWeekdays: number[] = session.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];
      const d = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
      setDates(d);

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
          await loadExisting(member.id, d);
        }
      }

      const params2 = new URLSearchParams(window.location.search);
      if (params2.get("synced") === "1") {
        const rowsCount = params2.get("rows");
        setJustSynced(`Synced from Google Calendar — ${rowsCount ?? "some"} time slots marked red below.`);
        const ctxParam = params2.get("ctx");
        if (ctxParam) {
          try {
            const decoded = JSON.parse(atob(ctxParam.replace(/-/g, "+").replace(/_/g, "/")));
            setEventContext(decoded);
          } catch {
            // ignore malformed context
          }
        }
        window.history.replaceState({}, "", window.location.pathname);
      }
      if (params2.get("sync_error") === "1") {
        const detail = params2.get("detail");
        setSyncError(detail ? decodeURIComponent(detail) : "Something went wrong syncing your calendar.");
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
    await loadExisting(member.id, dates);
  };

  const connectGoogle = () => {
    if (!memberId) return;
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    window.location.href = `/api/auth/google/start?session=${params.id}&member=${memberId}&tz=${encodeURIComponent(tz)}`;
  };

  const handlePaint = (date: string, block: number, value: Status) => {
    setStatuses((prev) => ({ ...prev, [cellKey(date, block)]: value }));
  };

  const submit = async () => {
    if (!memberId) return;
    setSubmitting(true);

    const rows: any[] = [];
    dates.forEach((date, day_index) => {
      blocks.forEach((_, block_index) => {
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
            Nobody sees your reasons — only red, yellow, or green. If you sync your calendar, event
            names are shown only to you on this screen so you have context to adjust things — they
            are never saved and never shown to anyone else.
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

            {syncError && (
              <div className="bg-[#2A1616] border border-[#FF5A5F] rounded-lg p-3 text-sm text-[#FF5A5F] mb-4">
                Sync failed: {syncError}
              </div>
            )}

            {justSynced && (
              <div className="bg-[#1C2A22] border border-[#35D07F] rounded-lg p-3 text-sm text-[#35D07F] mb-4">
                {justSynced}
              </div>
            )}

            {Object.keys(eventContext).length > 0 && (
              <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg p-3 mb-4">
                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                  What's blocking these (only you can see this)
                </div>
                <div className="space-y-1.5 max-h-48 overflow-y-auto">
                  {Object.entries(eventContext).map(([key, titles]) => {
                    const [date, blockStr] = key.split("|");
                    const block = Number(blockStr);
                    const label = blocks[block]?.label ?? `Block ${block}`;
                    const d = new Date(date + "T00:00:00");
                    const short = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
                    return (
                      <div key={key} className="text-xs text-gray-300">
                        <span className="font-bold">{short} {label}:</span> {titles.join(", ")}
                      </div>
                    );
                  })}
                </div>
                <div className="text-[11px] text-gray-500 mt-2">
                  If any of these can move, click that day above to change it from red.
                </div>
              </div>
            )}

            <button
              onClick={connectGoogle}
              className="w-full mb-4 py-2.5 rounded-lg border text-sm font-bold"
              style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#C7C9D1" }}
            >
              📅 Auto-fill from Google Calendar
            </button>

            <InteractivePaintCalendar
              startDate={startDate}
              endDate={endDate}
              dates={dates}
              blocks={blocks}
              statuses={statuses}
              eventContext={eventContext}
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
echo "Writing organizer page..."
cat > "app/session/[id]/organizer/page.tsx" << 'ORG_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { dateRangeFiltered, formatFullDate } from "@/lib/dates";
import { SummaryPaintCalendar, BlockDef, cellKey } from "@/components/Calendar";

interface Suggestion {
  date: string;
  block: number;
  blurb: string;
}

export default function OrganizerPage({ params }: { params: { id: string } }) {
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [blocks, setBlocks] = useState<BlockDef[]>([]);
  const [dates, setDates] = useState<string[]>([]);
  const [counts, setCounts] = useState<Record<string, { green: number; yellow: number; red: number }>>({});
  const [total, setTotal] = useState(0);
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");

  useEffect(() => {
    const load = async () => {
      const { data: session, error: sessionError } = await supabase
        .from("sessions")
        .select("start_date, end_date, blocks, active_weekdays")
        .eq("id", params.id)
        .single();

      if (sessionError || !session?.start_date || !session?.end_date) {
        setLoadError("This session doesn't have a date range set up yet.");
        setLoading(false);
        return;
      }

      setStartDate(session.start_date);
      setEndDate(session.end_date);
      const sessionBlocks: BlockDef[] = session.blocks ?? [];
      setBlocks(sessionBlocks);
      const activeWeekdays: number[] = session.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];
      const d = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
      setDates(d);

      const res = await fetch(`/api/session/${params.id}/suggest`);
      const json = await res.json();

      const grouped: Record<string, { green: number; yellow: number; red: number }> = {};
      let max = 0;
      (json.allCounts ?? []).forEach((c: any) => {
        const date = d[c.day_index];
        if (date) {
          grouped[cellKey(date, c.block_index)] = c;
          max = Math.max(max, c.responded);
        }
      });
      setCounts(grouped);
      setTotal(max);
      setSuggestions(
        (json.suggestions ?? []).map((s: any) => ({
          date: d[s.day_index],
          block: s.block_index,
          blurb: s.blurb,
        }))
      );
      setLoading(false);
    };
    load();
  }, [params.id]);

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <h1 className="text-2xl font-black uppercase mb-1">Group view</h1>
        <p className="text-sm text-gray-400 mb-6">
          Darker green = more people free. Nobody's individual answer is shown here.
        </p>

        {loadError ? (
          <p className="text-[#FF5A5F] text-sm">{loadError}</p>
        ) : loading ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : (
          <>
            <div className="mb-7">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                Suggested windows
              </div>
              {suggestions.length === 0 ? (
                <p className="text-sm text-gray-400">No clean windows yet — need a few more responses.</p>
              ) : (
                suggestions.map((s) => (
                  <div
                    key={`${s.date}-${s.block}`}
                    className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl px-3.5 py-3 mb-2 flex justify-between items-center"
                  >
                    <div>
                      <div className="font-bold text-sm">
                        {formatFullDate(s.date)} — {blocks[s.block]?.label ?? ""}
                      </div>
                      <div className="text-xs text-gray-400 mt-0.5">{s.blurb}</div>
                    </div>
                    <div
                      className="rounded-full flex-shrink-0"
                      style={{ width: 26, height: 26, background: "#35D07F", boxShadow: "0 0 10px #35D07F88" }}
                    />
                  </div>
                ))
              )}
            </div>

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">Calendar</div>
            <SummaryPaintCalendar startDate={startDate} endDate={endDate} dates={dates} blocks={blocks} counts={counts} total={total} />
          </>
        )}
      </div>
    </main>
  );
}
ORG_EOF
echo "Writing OAuth callback route..."
cat > "app/api/auth/google/callback/route.ts" << 'CALLBACK_EOF'
import { NextResponse } from "next/server";
import { exchangeCode, fetchEvents, eventsForRange } from "@/lib/google";
import { supabase } from "@/lib/supabase";
import { supabaseAdmin } from "@/lib/supabaseAdmin";
import { dateRangeFiltered } from "@/lib/dates";
import { BlockDef } from "@/components/Calendar";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const stateRaw = url.searchParams.get("state");
  if (!code || !stateRaw) {
    return NextResponse.redirect(new URL("/", url.origin));
  }

  const { sessionId, memberId, tz } = JSON.parse(Buffer.from(stateRaw, "base64url").toString());

  const { data: session } = await supabase
    .from("sessions")
    .select("start_date, end_date, blocks, active_weekdays")
    .eq("id", sessionId)
    .single();

  if (!session?.start_date || !session?.end_date) {
    return NextResponse.redirect(new URL(`/session/${sessionId}/respond`, url.origin));
  }

  const blocks: BlockDef[] = session.blocks ?? [];
  const activeWeekdays: number[] = session.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];

  let accessToken: string;
  try {
    accessToken = await exchangeCode(code);
  } catch (e: any) {
    const msg = encodeURIComponent(e?.message || "token exchange failed");
    return NextResponse.redirect(
      new URL(`/session/${sessionId}/respond?sync_error=1&detail=${msg}`, url.origin)
    );
  }

  const timeMin = new Date(session.start_date + "T00:00:00Z").toISOString();
  const timeMaxDate = new Date(session.end_date + "T00:00:00Z");
  timeMaxDate.setUTCDate(timeMaxDate.getUTCDate() + 1);
  const timeMax = timeMaxDate.toISOString();

  let events;
  try {
    events = await fetchEvents(accessToken, timeMin, timeMax, tz);
  } catch (e: any) {
    const msg = encodeURIComponent(e?.message || "calendar fetch failed");
    return NextResponse.redirect(
      new URL(`/session/${sessionId}/respond?sync_error=1&detail=${msg}`, url.origin)
    );
  }

  const dates = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
  const rows: any[] = [];
  const context: Record<string, string[]> = {};

  dates.forEach((date, day_index) => {
    blocks.forEach((block, block_index) => {
      const titles = eventsForRange(date, block.start_hour, block.end_hour, tz, events);
      if (titles.length > 0) {
        rows.push({
          session_id: sessionId,
          member_id: memberId,
          day_index,
          block_index,
          status: "red",
        });
        context[`${date}|${block_index}`] = titles.slice(0, 3).map((t) => t.slice(0, 60));
      }
    });
  });

  if (rows.length > 0) {
    const { error: upsertError } = await supabaseAdmin
      .from("availability")
      .upsert(rows, { onConflict: "session_id,member_id,day_index,block_index" });
    if (upsertError) {
      const msg = encodeURIComponent(upsertError.message);
      return NextResponse.redirect(
        new URL(`/session/${sessionId}/respond?sync_error=1&detail=${msg}`, url.origin)
      );
    }
  }

  const ctxEncoded = Buffer.from(JSON.stringify(context)).toString("base64url");

  return NextResponse.redirect(
    new URL(
      `/session/${sessionId}/respond?synced=1&rows=${rows.length}&ctx=${ctxEncoded}`,
      url.origin
    )
  );
}
CALLBACK_EOF
echo "Writing session-creation form..."
mkdir -p app/create
cat > "app/create/page.tsx" << 'CREATE_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { BlockDef, SIMPLE_BLOCKS, WHOLE_DAY_BLOCKS } from "@/components/Calendar";

type Mode = "simple" | "whole_day" | "custom";

const WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function formatHour(h: number): string {
  if (h === 24) return "12:00 AM (next day)";
  const period = h < 12 ? "AM" : "PM";
  let h12 = h % 12;
  if (h12 === 0) h12 = 12;
  return `${h12}:00 ${period}`;
}

export default function CreatePage() {
  const [checking, setChecking] = useState(true);
  const [userId, setUserId] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");

  const [bands, setBands] = useState<{ id: string; name: string }[]>([]);
  const [bandId, setBandId] = useState<string | null>(null);
  const [newBandName, setNewBandName] = useState("");
  const [creatingBand, setCreatingBand] = useState(false);

  const [title, setTitle] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [mode, setMode] = useState<Mode>("simple");
  const [activeWeekdays, setActiveWeekdays] = useState<number[]>([0, 1, 2, 3, 4, 5, 6]);
  const [customBlocks, setCustomBlocks] = useState<BlockDef[]>([
    { label: "", start_hour: 9, end_hour: 17 },
  ]);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState("");
  const [resultLink, setResultLink] = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) {
        setUserId(data.session.user.id);
        await loadBands(data.session.user.id);
      }
      setChecking(false);
    };
    load();
  }, []);

  const loadBands = async (uid: string) => {
    const { data } = await supabase.from("bands").select("id, name").eq("owner_id", uid);
    setBands(data ?? []);
    if (data && data.length === 1) setBandId(data[0].id);
  };

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password.");
      return;
    }
    setUserId(data.user.id);
    await loadBands(data.user.id);
  };

  const createBand = async () => {
    if (!newBandName.trim() || !userId) return;
    setCreatingBand(true);
    const { data, error } = await supabase
      .from("bands")
      .insert({ name: newBandName.trim(), owner_id: userId })
      .select()
      .single();
    setCreatingBand(false);
    if (!error && data) {
      setBands((prev) => [...prev, data]);
      setBandId(data.id);
      setNewBandName("");
    }
  };

  const toggleWeekday = (d: number) => {
    setActiveWeekdays((prev) =>
      prev.includes(d) ? prev.filter((x) => x !== d) : [...prev, d].sort()
    );
  };

  const addCustomBlock = () => {
    setCustomBlocks((prev) => [...prev, { label: "", start_hour: 9, end_hour: 17 }]);
  };
  const updateCustomBlock = (i: number, patch: Partial<BlockDef>) => {
    setCustomBlocks((prev) => prev.map((b, idx) => (idx === i ? { ...b, ...patch } : b)));
  };
  const removeCustomBlock = (i: number) => {
    setCustomBlocks((prev) => prev.filter((_, idx) => idx !== i));
  };

  const createSession = async () => {
    if (!bandId || !title.trim() || !startDate || !endDate) return;
    setCreateError("");
    setCreating(true);

    let blocks: BlockDef[];
    if (mode === "simple") blocks = SIMPLE_BLOCKS;
    else if (mode === "whole_day") blocks = WHOLE_DAY_BLOCKS;
    else blocks = customBlocks.filter((b) => b.label.trim());

    if (mode === "custom" && blocks.length === 0) {
      setCreateError("Add at least one named block for custom mode.");
      setCreating(false);
      return;
    }

    const { data, error } = await supabase
      .from("sessions")
      .insert({
        band_id: bandId,
        title: title.trim(),
        start_date: startDate,
        end_date: endDate,
        mode,
        blocks,
        active_weekdays: activeWeekdays,
      })
      .select()
      .single();

    setCreating(false);
    if (error || !data) {
      setCreateError(error?.message || "Couldn't create session.");
      return;
    }

    const link = `${window.location.origin}/join/${bandId}?session=${data.id}`;
    setResultLink(link);
  };

  const copyLink = () => {
    if (resultLink) navigator.clipboard.writeText(resultLink);
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <div className="flex gap-2 mb-2">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-2xl font-black uppercase tracking-tight mb-6">New Session</h1>

        {checking ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : !userId ? (
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
        ) : resultLink ? (
          <div>
            <p className="text-[#35D07F] text-sm mb-3">Session created. Share this link:</p>
            <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg p-3 text-xs text-gray-300 break-all mb-3">
              {resultLink}
            </div>
            <button
              onClick={copyLink}
              className="w-full py-2.5 rounded-lg border text-sm font-bold mb-3"
              style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#C7C9D1" }}
            >
              Copy link
            </button>
            <button
              onClick={() => {
                setResultLink(null);
                setTitle("");
                setStartDate("");
                setEndDate("");
              }}
              className="w-full py-2.5 rounded-lg text-sm font-bold"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              Create another session
            </button>
          </div>
        ) : (
          <>
            {/* Band picker */}
            <div className="mb-5">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">Band</div>
              {bands.length > 0 && (
                <div className="flex flex-wrap gap-2 mb-2">
                  {bands.map((b) => (
                    <button
                      key={b.id}
                      onClick={() => setBandId(b.id)}
                      className="px-3 py-1.5 rounded-lg border text-sm font-bold"
                      style={{
                        borderColor: bandId === b.id ? "#35D07F" : "#2C2F38",
                        background: bandId === b.id ? "#1C2A22" : "transparent",
                        color: bandId === b.id ? "#35D07F" : "#C7C9D1",
                      }}
                    >
                      {b.name}
                    </button>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <input
                  value={newBandName}
                  onChange={(e) => setNewBandName(e.target.value)}
                  placeholder="New band name"
                  className="flex-1 box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                />
                <button
                  onClick={createBand}
                  disabled={creatingBand || !newBandName.trim()}
                  className="px-3 py-2 rounded-lg text-sm font-bold"
                  style={{ background: "#35D07F", color: "#0E1712" }}
                >
                  + Add
                </button>
              </div>
            </div>

            {bandId && (
              <>
                <input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Session title (e.g. September rehearsals)"
                  className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
                />

                <div className="flex gap-2 mb-4">
                  <div className="flex-1">
                    <div className="text-xs text-gray-400 mb-1">Start date</div>
                    <input
                      type="date"
                      value={startDate}
                      onChange={(e) => setStartDate(e.target.value)}
                      className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                    />
                  </div>
                  <div className="flex-1">
                    <div className="text-xs text-gray-400 mb-1">End date</div>
                    <input
                      type="date"
                      value={endDate}
                      onChange={(e) => setEndDate(e.target.value)}
                      className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                    />
                  </div>
                </div>

                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                  Time frame
                </div>
                <div className="flex gap-2 mb-4">
                  {[
                    { value: "simple" as Mode, label: "Simple (AM/Mid/PM)" },
                    { value: "whole_day" as Mode, label: "Whole days only" },
                    { value: "custom" as Mode, label: "Custom" },
                  ].map((m) => (
                    <button
                      key={m.value}
                      onClick={() => setMode(m.value)}
                      className="flex-1 py-2 rounded-lg border text-xs font-bold"
                      style={{
                        borderColor: mode === m.value ? "#35D07F" : "#2C2F38",
                        background: mode === m.value ? "#1C2A22" : "transparent",
                        color: mode === m.value ? "#35D07F" : "#8B8E98",
                      }}
                    >
                      {m.label}
                    </button>
                  ))}
                </div>

                {mode === "custom" && (
                  <div className="mb-4">
                    <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                      Blocks
                    </div>
                    {customBlocks.map((b, i) => (
                      <div key={i} className="flex gap-2 mb-2 items-center">
                        <input
                          value={b.label}
                          onChange={(e) => updateCustomBlock(i, { label: e.target.value })}
                          placeholder="e.g. Load-in"
                          className="flex-1 box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-2 py-2 text-sm outline-none"
                        />
                        <select
                          value={b.start_hour}
                          onChange={(e) => updateCustomBlock(i, { start_hour: Number(e.target.value) })}
                          className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-1 py-2 text-xs outline-none"
                        >
                          {Array.from({ length: 24 }, (_, h) => (
                            <option key={h} value={h}>{formatHour(h)}</option>
                          ))}
                        </select>
                        <span className="text-gray-500 text-xs">to</span>
                        <select
                          value={b.end_hour}
                          onChange={(e) => updateCustomBlock(i, { end_hour: Number(e.target.value) })}
                          className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-1 py-2 text-xs outline-none"
                        >
                          {Array.from({ length: 24 }, (_, h) => h + 1).map((h) => (
                            <option key={h} value={h}>{formatHour(h)}</option>
                          ))}
                        </select>
                        <button
                          onClick={() => removeCustomBlock(i)}
                          className="text-[#FF5A5F] text-sm px-1"
                        >
                          ✕
                        </button>
                      </div>
                    ))}
                    <button
                      onClick={addCustomBlock}
                      className="text-xs font-bold text-[#35D07F]"
                    >
                      + Add block
                    </button>
                  </div>
                )}

                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                  Days that count
                </div>
                <div className="flex gap-1.5 mb-5">
                  {WEEKDAY_LABELS.map((label, i) => (
                    <button
                      key={i}
                      onClick={() => toggleWeekday(i)}
                      className="flex-1 py-2 rounded-lg border text-xs font-bold"
                      style={{
                        borderColor: activeWeekdays.includes(i) ? "#35D07F" : "#2C2F38",
                        background: activeWeekdays.includes(i) ? "#1C2A22" : "transparent",
                        color: activeWeekdays.includes(i) ? "#35D07F" : "#8B8E98",
                      }}
                    >
                      {label}
                    </button>
                  ))}
                </div>

                {createError && <p className="text-[#FF5A5F] text-xs mb-3">{createError}</p>}

                <button
                  onClick={createSession}
                  disabled={creating || !title.trim() || !startDate || !endDate}
                  className="w-full py-3 rounded-xl font-bold text-[15px]"
                  style={{ background: "#35D07F", color: "#0E1712" }}
                >
                  {creating ? "Creating…" : "Create session"}
                </button>
              </>
            )}
          </>
        )}
      </div>
    </main>
  );
}
CREATE_EOF
echo "All files updated."
