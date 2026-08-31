export type { CalEvent } from "./calendarMatch";
export { zonedTimeToUtc, eventsForRange } from "./calendarMatch";

const CLIENT_ID = process.env.GOOGLE_CLIENT_ID!;
const CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET!;
const REDIRECT_URI = process.env.GOOGLE_REDIRECT_URI!;

export function googleAuthUrl(state: string): string {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    response_type: "code",
    scope: "https://www.googleapis.com/auth/calendar.events.readonly",
    // "offline" + prompt=consent is what makes Google return a
    // refresh_token, not just a short-lived access_token -- needed so the
    // "My Calendar" unified connection (lib/myCalendar.ts) can re-sync
    // without the person re-clicking through Google's consent screen every
    // single visit. The existing per-session sync flow doesn't need the
    // refresh token and just ignores it -- exchangeCode() below still
    // returns only the access_token for that caller, unchanged.
    access_type: "offline",
    prompt: "consent",
    state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

export interface GoogleTokenSet {
  accessToken: string;
  refreshToken: string | null;
  expiresIn: number; // seconds
}

async function tokenRequest(body: Record<string, string>): Promise<any> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(body),
  });
  return res.json();
}

/** Full token exchange -- used by the "My Calendar" connect flow, which needs the refresh_token. */
export async function exchangeCodeForTokens(code: string): Promise<GoogleTokenSet> {
  const json = await tokenRequest({
    code,
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    redirect_uri: REDIRECT_URI,
    grant_type: "authorization_code",
  });
  if (!json.access_token) throw new Error(json.error_description || "Token exchange failed");
  return {
    accessToken: json.access_token as string,
    refreshToken: (json.refresh_token as string) ?? null,
    expiresIn: (json.expires_in as number) ?? 3600,
  };
}

/** Backward-compatible wrapper for the existing per-session sync flow -- just the access token. */
export async function exchangeCode(code: string): Promise<string> {
  const tokens = await exchangeCodeForTokens(code);
  return tokens.accessToken;
}

/**
 * Mints a fresh access token from a stored refresh token. Throws if the
 * refresh token has been revoked or expired -- including Google's 7-day
 * limit on refresh tokens for apps still in "Testing" publishing status.
 */
export async function refreshAccessToken(
  refreshToken: string
): Promise<{ accessToken: string; expiresIn: number }> {
  const json = await tokenRequest({
    refresh_token: refreshToken,
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    grant_type: "refresh_token",
  });
  if (!json.access_token) {
    throw new Error(
      json.error_description || json.error || "Refresh failed -- reconnect Google Calendar."
    );
  }
  return { accessToken: json.access_token as string, expiresIn: (json.expires_in as number) ?? 3600 };
}

import type { CalEvent } from "./calendarMatch";

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

/** The connected Google account's email -- shown as "Connected as X" on the My Calendar page. */
export async function fetchGoogleEmail(accessToken: string): Promise<string | null> {
  try {
    const res = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    const json = await res.json();
    return json.email ?? null;
  } catch {
    return null;
  }
}
