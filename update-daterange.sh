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
DATES_EOF
echo "Writing components/DateList.tsx..."
cat > "components/DateList.tsx" << 'DATELIST_EOF'
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
DATELIST_EOF
echo "Writing respond page..."
cat > "app/session/[id]/respond/page.tsx" << 'RESPOND_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { Status, STATUS_CYCLE } from "@/lib/types";
import { dateRange } from "@/lib/dates";
import { InteractiveDateList } from "@/components/DateList";

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
            <InteractiveDateList dates={dates} statuses={statuses} onToggle={toggle} />
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
import { SummaryDateList } from "@/components/DateList";

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

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">All days</div>
            <SummaryDateList dates={dates} counts={counts} total={total} />
          </>
        )}
      </div>
    </main>
  );
}
ORG_EOF
echo "Writing API route..."
cat > "app/api/session/[id]/suggest/route.ts" << 'API_EOF'
import { NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { topSuggestions, plainLine } from "@/lib/scoring";
import { CellCounts } from "@/lib/types";

// GET /api/session/[id]/suggest
// Reads only the aggregate counts (via the session_summary SQL function —
// see supabase/schema.sql) and ranks windows. The Claude call only writes
// the one-line "why", it never sees who responded or how.
export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const { data, error } = await supabase.rpc("session_summary", {
    p_session_id: params.id,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const cells = (data ?? []) as CellCounts[];
  const ranked = topSuggestions(cells);

  const withBlurbs = await Promise.all(
    ranked.map(async (s) => {
      const blurb = await writeBlurb(s.counts).catch(() => plainLine(s.counts));
      return { day_index: s.day_index, block_index: s.block_index, blurb };
    })
  );

  return NextResponse.json({ suggestions: withBlurbs, allCounts: cells });
}

async function writeBlurb(counts: CellCounts): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) return plainLine(counts);

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": process.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 60,
      messages: [
        {
          role: "user",
          content: `A band scheduling tool has a time slot with these counts: ${counts.green} free, ${counts.yellow} flexible, ${counts.red} busy, out of ${counts.responded} responses. Write one short, casual sentence (under 15 words) summarizing why this slot works. No names, no reasons for anyone's status, just the vibe of the numbers.`,
        },
      ],
    }),
  });

  const json = await res.json();
  const text = json?.content?.find((b: any) => b.type === "text")?.text;
  return text?.trim() || plainLine(counts);
}
API_EOF
echo "All files updated."
