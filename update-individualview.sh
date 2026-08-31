#!/bin/bash
set -e
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
cat > "app/session/[id]/organizer/page.tsx" << 'ORG_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { dateRangeFiltered, formatFullDate } from "@/lib/dates";
import { InteractivePaintCalendar, SummaryPaintCalendar, BlockDef, SIMPLE_BLOCKS, cellKey } from "@/components/Calendar";
import { Status } from "@/lib/types";

interface Suggestion {
  date: string;
  block: number;
  blurb: string;
}

export default function OrganizerPage({ params }: { params: { id: string } }) {
  const [checkingAuth, setCheckingAuth] = useState(true);
  const [authorized, setAuthorized] = useState(false);
  const [authError, setAuthError] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");

  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [blocks, setBlocks] = useState<BlockDef[]>([]);
  const [dates, setDates] = useState<string[]>([]);
  const [counts, setCounts] = useState<Record<string, { green: number; yellow: number; red: number }>>({});
  const [total, setTotal] = useState(0);
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [members, setMembers] = useState<{ id: string; name: string }[]>([]);
  const [memberStatuses, setMemberStatuses] = useState<Record<string, Record<string, Status>>>({});
  const [expandedMember, setExpandedMember] = useState<string | null>(null);

  const checkOwnership = async (userId: string, bandId: string) => {
    const { data: band } = await supabase
      .from("bands")
      .select("id")
      .eq("id", bandId)
      .eq("owner_id", userId)
      .single();
    return !!band;
  };

  const loadSessionData = async (bandId: string) => {
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
    const rawBlocks = session.blocks;
    const isValid =
      Array.isArray(rawBlocks) &&
      rawBlocks.length > 0 &&
      rawBlocks.every(
        (x: any) => x && typeof x.label === "string" && typeof x.start_hour === "number" && typeof x.end_hour === "number"
      );
    const sessionBlocks: BlockDef[] = isValid ? rawBlocks : SIMPLE_BLOCKS;
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

    // Individual responses — allowed by RLS for the band owner only.
    // Only colors are ever fetched here, never private_notes (event reasons).
    const { data: bandMembers } = await supabase
      .from("members")
      .select("id, name")
      .eq("band_id", bandId);
    setMembers(bandMembers ?? []);

    const { data: allAvailability } = await supabase
      .from("availability")
      .select("member_id, day_index, block_index, status")
      .eq("session_id", params.id);

    const perMember: Record<string, Record<string, Status>> = {};
    (allAvailability ?? []).forEach((row: any) => {
      const date = d[row.day_index];
      if (!date) return;
      if (!perMember[row.member_id]) perMember[row.member_id] = {};
      perMember[row.member_id][cellKey(date, row.block_index)] = row.status as Status;
    });
    setMemberStatuses(perMember);

    setLoading(false);
  };

  useEffect(() => {
    const init = async () => {
      const { data: session } = await supabase
        .from("sessions")
        .select("band_id")
        .eq("id", params.id)
        .single();

      if (!session?.band_id) {
        setAuthError("This session doesn't exist.");
        setCheckingAuth(false);
        return;
      }

      const { data: authData } = await supabase.auth.getSession();
      if (authData.session) {
        const owns = await checkOwnership(authData.session.user.id, session.band_id);
        if (owns) {
          setAuthorized(true);
          await loadSessionData(session.band_id);
        } else {
          setAuthError("You're not the organizer for this band's sessions.");
        }
      }
      setCheckingAuth(false);
    };
    init();
  }, [params.id]);

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password.");
      return;
    }
    const { data: session } = await supabase
      .from("sessions")
      .select("band_id")
      .eq("id", params.id)
      .single();
    if (!session?.band_id) {
      setAuthError("This session doesn't exist.");
      return;
    }
    const owns = await checkOwnership(data.user.id, session.band_id);
    if (!owns) {
      setAuthError("You're not the organizer for this band's sessions.");
      return;
    }
    setAuthorized(true);
    setLoading(true);
    await loadSessionData(session.band_id);
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <h1 className="text-2xl font-black uppercase mb-1">Group view</h1>
        <p className="text-sm text-gray-400 mb-6">
          Darker green = more people free. Nobody's individual answer is shown here.
        </p>

        {checkingAuth ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : !authorized ? (
          <div>
            {authError && <p className="text-[#FF5A5F] text-sm mb-3">{authError}</p>}
            <p className="text-sm text-gray-400 mb-3">Log in as the organizer to see this.</p>
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
        ) : loadError ? (
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

            {members.length > 0 && (
              <div className="mt-8">
                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                  Individual responses
                </div>
                <p className="text-xs text-gray-500 mb-3">
                  Colors only — nobody's reasons are ever visible here, only to them.
                </p>
                {members.map((m) => {
                  const isOpen = expandedMember === m.id;
                  const hasResponded = !!memberStatuses[m.id] && Object.keys(memberStatuses[m.id]).length > 0;
                  return (
                    <div key={m.id} className="mb-2">
                      <button
                        onClick={() => setExpandedMember(isOpen ? null : m.id)}
                        className="w-full flex justify-between items-center px-3.5 py-2.5 rounded-lg border text-sm"
                        style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#F2F1EA" }}
                      >
                        <span className="font-bold">{m.name}</span>
                        <span className="text-xs text-gray-500">
                          {hasResponded ? (isOpen ? "Hide ▲" : "View ▼") : "No response yet"}
                        </span>
                      </button>
                      {isOpen && hasResponded && (
                        <div className="mt-2 pl-1">
                          <InteractivePaintCalendar
                            startDate={startDate}
                            endDate={endDate}
                            dates={dates}
                            blocks={blocks}
                            statuses={memberStatuses[m.id]}
                            onPaint={() => {}}
                            readOnly
                          />
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </>
        )}
      </div>
    </main>
  );
}
ORG_EOF
echo done
