#!/bin/bash
set -e
echo "Writing lib/google.ts (final hardened fix)..."
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

function getTimeZoneOffsetMinutes(date: Date, timeZone: string): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
  const parts = dtf.formatToParts(date);
  const map: Record<string, string> = {};
  for (const p of parts) if (p.type !== "literal") map[p.type] = p.value;
  const asUTC = Date.UTC(
    Number(map.year),
    Number(map.month) - 1,
    Number(map.day),
    Number(map.hour),
    Number(map.minute),
    Number(map.second)
  );
  return (asUTC - date.getTime()) / 60000;
}

export function zonedTimeToUtc(dateISO: string, hour: number, timeZone: string): Date {
  let d = dateISO;
  let h = hour;
  if (h >= 24) {
    // Advance to the next calendar day using plain arithmetic on the
    // Y/M/D parts — no Date formatting involved, so this can't throw
    // even if something upstream is unusual.
    const [y, m, day] = dateISO.split("-").map(Number);
    const nextTimestamp = Date.UTC(y, m - 1, day + 1);
    const nextDate = new Date(nextTimestamp);
    const yy = nextDate.getUTCFullYear();
    const mm = String(nextDate.getUTCMonth() + 1).padStart(2, "0");
    const dd = String(nextDate.getUTCDate()).padStart(2, "0");
    d = `${yy}-${mm}-${dd}`;
    h = h - 24;
  }
  const naiveUtc = new Date(`${d}T${String(h).padStart(2, "0")}:00:00Z`);
  const offsetMinutes = getTimeZoneOffsetMinutes(naiveUtc, timeZone);
  return new Date(naiveUtc.getTime() - offsetMinutes * 60000);
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
echo "Writing OAuth callback route (with stack trace on error)..."
cat > "app/api/auth/google/callback/route.ts" << 'CALLBACK_EOF'
import { NextResponse } from "next/server";
import { exchangeCode, fetchEvents, eventsForRange, zonedTimeToUtc } from "@/lib/google";
import { supabase } from "@/lib/supabase";
import { supabaseAdmin } from "@/lib/supabaseAdmin";
import { dateRangeFiltered } from "@/lib/dates";
import { BlockDef } from "@/components/Calendar";

export async function GET(req: Request) {
  const url = new URL(req.url);
  // Captured as soon as we know it, so that even an unexpected failure
  // later on can send the person back to their own calendar with a
  // real error message instead of a dead-end homepage.
  let sessionId: string | undefined;

  try {
    const code = url.searchParams.get("code");
    const stateRaw = url.searchParams.get("state");
    if (!code || !stateRaw) {
      return NextResponse.redirect(new URL("/", url.origin));
    }

    const parsedState = JSON.parse(Buffer.from(stateRaw, "base64url").toString());
    sessionId = parsedState.sessionId;
    const memberId: string = parsedState.memberId;
    const tz: string = parsedState.tz;

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

    // Dates from Supabase should already be plain "YYYY-MM-DD" strings, but
    // guard this explicitly — this exact spot was previously unprotected
    // and could throw "Invalid time value" straight past every other
    // safety net in this file.
    let timeMin: string;
    let timeMax: string;
    try {
      const startStr = String(session.start_date).slice(0, 10);
      const endStr = String(session.end_date).slice(0, 10);
      const minDate = new Date(`${startStr}T00:00:00Z`);
      const maxDate = new Date(`${endStr}T00:00:00Z`);
      if (isNaN(minDate.getTime()) || isNaN(maxDate.getTime())) {
        throw new Error(`bad session dates: start=${startStr} end=${endStr}`);
      }
      maxDate.setUTCDate(maxDate.getUTCDate() + 1);
      timeMin = minDate.toISOString();
      timeMax = maxDate.toISOString();
    } catch (e: any) {
      const msg = encodeURIComponent(e?.message || "invalid session dates");
      return NextResponse.redirect(
        new URL(`/session/${sessionId}/respond?sync_error=1&detail=${msg}`, url.origin)
      );
    }

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
    const noteRows: any[] = [];

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
          noteRows.push({
            session_id: sessionId,
            member_id: memberId,
            day_index,
            block_index,
            titles: titles.slice(0, 3).map((t) => t.slice(0, 60)),
          });
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

    let noteError: string | null = null;
    if (noteRows.length > 0) {
      const { error } = await supabaseAdmin
        .from("private_notes")
        .upsert(noteRows, { onConflict: "session_id,member_id,day_index,block_index" });
      if (error) noteError = error.message;
    }
    const noteErrorParam = noteError ? `&note_error=${encodeURIComponent(noteError)}` : "";

    const sample = events
      .slice(0, 3)
      .map((e) => `${e.title} [${e.start} to ${e.end}]`)
      .join(" | ");
    const sampleParam = sample ? `&sample=${encodeURIComponent(sample)}` : "";

    return NextResponse.redirect(
      new URL(
        `/session/${sessionId}/respond?synced=1&rows=${rows.length}&events=${events.length}${noteErrorParam}${sampleParam}`,
        url.origin
      )
    );
  } catch (e: any) {
    const stackLine = e?.stack?.split("\n").slice(0, 2).join(" || ") || "";
    const msg = encodeURIComponent(`${e?.message || "unexpected error"} :: ${stackLine}`);
    if (sessionId) {
      return NextResponse.redirect(
        new URL(`/session/${sessionId}/respond?sync_error=1&detail=${msg}`, url.origin)
      );
    }
    return NextResponse.redirect(new URL(`/?crash=1&detail=${msg}`, url.origin));
  }
}
CALLBACK_EOF
echo "Done."
