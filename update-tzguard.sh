#!/bin/bash
set -e
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

function safeTimeZone(tz: string): string {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return "America/Chicago";
  }
}

function getTimeZoneOffsetMinutes(date: Date, timeZone: string): number {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: safeTimeZone(timeZone),
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
echo done
