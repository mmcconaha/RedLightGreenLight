#!/bin/bash
set -e
echo "Writing lib/google.ts..."
mkdir -p lib
cat > "lib/google.ts" << 'GOOGLE_EOF'
const CLIENT_ID = process.env.GOOGLE_CLIENT_ID!;
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET!;
const REDIRECT_URI = process.env.GOOGLE_REDIRECT_URI!;

export function googleAuthUrl(state: string): string {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    response_type: "code",
    // freebusy only — never event titles, locations, or attendees
    scope: "https://www.googleapis.com/auth/calendar.freebusy",
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

export interface BusyInterval {
  start: string;
  end: string;
}

export async function fetchFreeBusy(
  accessToken: string,
  timeMinISO: string,
  timeMaxISO: string,
  timeZone: string
): Promise<BusyInterval[]> {
  const res = await fetch("https://www.googleapis.com/calendar/v3/freeBusy", {
    method: "POST",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      timeMin: timeMinISO,
      timeMax: timeMaxISO,
      timeZone,
      items: [{ id: "primary" }],
    }),
  });
  const json = await res.json();
  return json?.calendars?.primary?.busy ?? [];
}

// Fixed local-time windows for each block, in 24hr hours.
export const BLOCK_HOURS: [number, number][] = [
  [6, 12], // Morning
  [12, 17], // Midday
  [17, 22], // Evening
];

function zonedTimeToUtc(dateISO: string, hour: number, timeZone: string): Date {
  const naiveUtc = new Date(`${dateISO}T${String(hour).padStart(2, "0")}:00:00Z`);
  const asIfLocal = new Date(naiveUtc.toLocaleString("en-US", { timeZone }));
  const asIfUtc = new Date(naiveUtc.toLocaleString("en-US", { timeZone: "UTC" }));
  const offset = asIfUtc.getTime() - asIfLocal.getTime();
  return new Date(naiveUtc.getTime() + offset);
}

export function blockOverlapsBusy(
  dateISO: string,
  block: number,
  timeZone: string,
  busy: BusyInterval[]
): boolean {
  const [startHour, endHour] = BLOCK_HOURS[block];
  const blockStart = zonedTimeToUtc(dateISO, startHour, timeZone);
  const blockEnd = zonedTimeToUtc(dateISO, endHour, timeZone);
  return busy.some((b) => {
    const busyStart = new Date(b.start);
    const busyEnd = new Date(b.end);
    return busyStart < blockEnd && busyEnd > blockStart;
  });
}
GOOGLE_EOF
echo "Writing OAuth start route..."
mkdir -p "app/api/auth/google/start"
cat > "app/api/auth/google/start/route.ts" << 'START_EOF'
import { NextResponse } from "next/server";
import { googleAuthUrl } from "@/lib/google";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const sessionId = url.searchParams.get("session");
  const memberId = url.searchParams.get("member");
  const tz = url.searchParams.get("tz") || "America/Chicago";

  if (!sessionId || !memberId) {
    return NextResponse.json({ error: "Missing session or member" }, { status: 400 });
  }

  const state = Buffer.from(JSON.stringify({ sessionId, memberId, tz })).toString("base64url");
  return NextResponse.redirect(googleAuthUrl(state));
}
START_EOF
echo "Writing OAuth callback route..."
mkdir -p "app/api/auth/google/callback"
cat > "app/api/auth/google/callback/route.ts" << 'CALLBACK_EOF'
import { NextResponse } from "next/server";
import { exchangeCode, fetchFreeBusy, blockOverlapsBusy } from "@/lib/google";
import { supabase } from "@/lib/supabase";
import { dateRange } from "@/lib/dates";

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
    .select("start_date, end_date")
    .eq("id", sessionId)
    .single();

  if (!session?.start_date || !session?.end_date) {
    return NextResponse.redirect(new URL(`/session/${sessionId}/respond`, url.origin));
  }

  let accessToken: string;
  try {
    accessToken = await exchangeCode(code);
  } catch (e) {
    return NextResponse.redirect(new URL(`/session/${sessionId}/respond?sync_error=1`, url.origin));
  }

  const timeMin = new Date(session.start_date + "T00:00:00Z").toISOString();
  const timeMaxDate = new Date(session.end_date + "T00:00:00Z");
  timeMaxDate.setUTCDate(timeMaxDate.getUTCDate() + 1);
  const timeMax = timeMaxDate.toISOString();

  const busy = await fetchFreeBusy(accessToken, timeMin, timeMax, tz);

  const dates = dateRange(session.start_date, session.end_date);
  const rows: any[] = [];
  dates.forEach((date, day_index) => {
    [0, 1, 2].forEach((block_index) => {
      if (blockOverlapsBusy(date, block_index, tz, busy)) {
        rows.push({
          session_id: sessionId,
          member_id: memberId,
          day_index,
          block_index,
          status: "red",
        });
      }
    });
  });

  if (rows.length > 0) {
    await supabase
      .from("availability")
      .upsert(rows, { onConflict: "session_id,member_id,day_index,block_index" });
  }

  return NextResponse.redirect(new URL(`/session/${sessionId}/respond?synced=1`, url.origin));
}
CALLBACK_EOF
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
  const [justSynced, setJustSynced] = useState(false);

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
      const d = dateRange(session.start_date, session.end_date);
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
      if (params2.get("synced") === "1") setJustSynced(true);

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

            {justSynced && (
              <div className="bg-[#1C2A22] border border-[#35D07F] rounded-lg p-3 text-sm text-[#35D07F] mb-4">
                Synced from Google Calendar — busy blocks are marked red below. Review and adjust
                anything, then send.
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
echo "All files written."
