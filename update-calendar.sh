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
DATES_EOF
echo "Writing components/Calendar.tsx..."
cat > "components/Calendar.tsx" << 'CAL_EOF'
"use client";

import { Status } from "@/lib/types";
import { monthGrid, monthsInRange } from "@/lib/dates";

const STATUS_COLOR: Record<Status, string> = {
  unset: "#2C2F38",
  green: "#35D07F",
  yellow: "#FFC24B",
  red: "#FF5A5F",
};

const WEEKDAY_LABELS = ["S", "M", "T", "W", "T", "F", "S"];

export function InteractiveCalendar({
  dates,
  statuses,
  onToggle,
}: {
  dates: string[];
  statuses: Record<string, Status>;
  onToggle: (date: string) => void;
}) {
  const validDates = new Set(dates);
  const months = monthsInRange(dates);

  return (
    <div>
      {months.map(({ year, month, label }) => (
        <div key={`${year}-${month}`} className="mb-6">
          <div className="text-sm font-bold uppercase tracking-wide text-gray-300 mb-2">{label}</div>
          <div className="grid grid-cols-7 gap-1 mb-1">
            {WEEKDAY_LABELS.map((w, i) => (
              <div key={i} className="text-center text-[10px] text-gray-500 font-bold">
                {w}
              </div>
            ))}
          </div>
          {monthGrid(year, month).map((week, wi) => (
            <div key={wi} className="grid grid-cols-7 gap-1 mb-1">
              {week.map((iso, di) => {
                if (!iso || !validDates.has(iso)) {
                  return <div key={di} className="aspect-square" />;
                }
                const status = statuses[iso] ?? "unset";
                const dayNum = Number(iso.split("-")[2]);
                return (
                  <button
                    key={di}
                    onClick={() => onToggle(iso)}
                    className="aspect-square rounded-lg border flex items-center justify-center text-sm font-semibold"
                    style={{
                      borderColor: "#2C2F38",
                      background: STATUS_COLOR[status],
                      color: status === "unset" ? "#8B8E98" : "#0E1712",
                    }}
                  >
                    {dayNum}
                  </button>
                );
              })}
            </div>
          ))}
        </div>
      ))}
      <div className="flex gap-4 mt-2 text-xs text-gray-400">
        <Legend color={STATUS_COLOR.green} label="Free" />
        <Legend color={STATUS_COLOR.yellow} label="Flexible" />
        <Legend color={STATUS_COLOR.red} label="Busy" />
      </div>
    </div>
  );
}

export function SummaryCalendar({
  dates,
  counts,
  total,
}: {
  dates: string[];
  counts: Record<string, { green: number; yellow: number; red: number }>;
  total: number;
}) {
  const validDates = new Set(dates);
  const months = monthsInRange(dates);
  const t = total || 1;

  return (
    <div>
      {months.map(({ year, month, label }) => (
        <div key={`${year}-${month}`} className="mb-6">
          <div className="text-sm font-bold uppercase tracking-wide text-gray-300 mb-2">{label}</div>
          <div className="grid grid-cols-7 gap-1 mb-1">
            {WEEKDAY_LABELS.map((w, i) => (
              <div key={i} className="text-center text-[10px] text-gray-500 font-bold">
                {w}
              </div>
            ))}
          </div>
          {monthGrid(year, month).map((week, wi) => (
            <div key={wi} className="grid grid-cols-7 gap-1 mb-1">
              {week.map((iso, di) => {
                if (!iso || !validDates.has(iso)) {
                  return <div key={di} className="aspect-square" />;
                }
                const c = counts[iso] ?? { green: 0, yellow: 0, red: 0 };
                let bg = "#2C2F38";
                if (c.red > 0) bg = `rgba(255,90,95,${0.25 + 0.5 * (c.red / t)})`;
                else if (c.green === t && t > 0) bg = "#35D07F";
                else if (c.green + c.yellow > 0) bg = `rgba(53,208,127,${0.2 + 0.6 * (c.green / t)})`;
                const dayNum = Number(iso.split("-")[2]);
                return (
                  <div
                    key={di}
                    title={`${c.green} free, ${c.yellow} flexible, ${c.red} busy`}
                    className="aspect-square rounded-lg border flex items-center justify-center text-sm font-semibold"
                    style={{ borderColor: "#2C2F38", background: bg, color: "#F2F1EA" }}
                  >
                    {dayNum}
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <div className="flex items-center gap-1">
      <div className="w-2 h-2 rounded-full" style={{ background: color }} />
      {label}
    </div>
  );
}
CAL_EOF
echo "Writing respond page..."
cat > "app/session/[id]/respond/page.tsx" << 'RESPOND_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { Status, STATUS_CYCLE } from "@/lib/types";
import { dateRange } from "@/lib/dates";
import { InteractiveCalendar } from "@/components/Calendar";

export default function RespondPage({ params }: { params: { id: string } }) {
  const [checkingSession, setCheckingSession] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState("");

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

  const toggle = (date: string) => {
    setStatuses((prev) => {
      const cur = prev[date] ?? "unset";
      const next = STATUS_CYCLE[(STATUS_CYCLE.indexOf(cur) + 1) % STATUS_CYCLE.length];
      return { ...prev, [date]: next };
    });
  };

  const submit = async () => {
    if (!memberId) return;
    setSubmitting(true);

    const rows = dates
      .map((date, day_index) => ({ day_index, status: statuses[date] ?? "unset" }))
      .filter((r) => r.status !== "unset")
      .map((r) => ({
        session_id: params.id,
        member_id: memberId,
        day_index: r.day_index,
        block_index: 0,
        status: r.status,
      }));

    await supabase
      .from("availability")
      .upsert(rows, { onConflict: "session_id,member_id,day_index,block_index" });

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
          One tap per day tells the band if you're free. No calendar, no explaining, no guilt.
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
            <p className="text-sm text-gray-300 mb-1">
              Hey {memberName} — tap each day below ({dates.length} days total):
            </p>
            <InteractiveCalendar dates={dates} statuses={statuses} onToggle={toggle} />
            <button
              onClick={submit}
              disabled={submitting}
              className="w-full mt-5 py-3 rounded-xl font-bold text-[15px]"
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
import { dateRange, formatFullDate } from "@/lib/dates";
import { SummaryCalendar } from "@/components/Calendar";

interface Suggestion {
  date: string;
  blurb: string;
}

export default function OrganizerPage({ params }: { params: { id: string } }) {
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
        .select("start_date, end_date")
        .eq("id", params.id)
        .single();

      if (sessionError || !session?.start_date || !session?.end_date) {
        setLoadError("This session doesn't have a date range set up yet.");
        setLoading(false);
        return;
      }

      const d = dateRange(session.start_date, session.end_date);
      setDates(d);

      const res = await fetch(`/api/session/${params.id}/suggest`);
      const json = await res.json();

      const grouped: Record<string, { green: number; yellow: number; red: number }> = {};
      let max = 0;
      (json.allCounts ?? []).forEach((c: any) => {
        const date = d[c.day_index];
        if (date) {
          grouped[date] = c;
          max = Math.max(max, c.responded);
        }
      });
      setCounts(grouped);
      setTotal(max);
      setSuggestions(
        (json.suggestions ?? []).map((s: any) => ({
          date: d[s.day_index],
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
                    key={s.date}
                    className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl px-3.5 py-3 mb-2 flex justify-between items-center"
                  >
                    <div>
                      <div className="font-bold text-sm">{formatFullDate(s.date)}</div>
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

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">Calendar</div>
            <SummaryCalendar dates={dates} counts={counts} total={total} />
          </>
        )}
      </div>
    </main>
  );
}
ORG_EOF
echo "All files updated."
