// Server-side helpers for the unified "My Calendar" page -- one Google
// and/or Apple connection per PERSON (not per band membership), covering
// every session across every band that person is part of. See
// supabase/user_calendar_connections_migration.sql for the table this
// reads/writes, and app/api/my-calendar/* for the routes that call these.
//
// Every read/write in this file uses supabaseAdmin (service role), not the
// anon client -- this all runs server-side with no browser session to
// carry auth.uid(), so RLS-scoped reads of members/availability would come
// back empty against the anon client. This file is never imported into any
// "use client" code.
import { supabaseAdmin } from "./supabaseAdmin";
import { encryptSecret, decryptSecret } from "./appleCrypto";
import { fetchAppleEvents, verifyAppleCredentials } from "./apple";
import { fetchEvents as fetchGoogleEvents, fetchGoogleEmail, refreshAccessToken } from "./google";
import type { CalEvent } from "./calendarMatch";
import { dateRangeFiltered } from "./dates";

export interface ConnectionStatus {
  google: { connected: boolean; email: string | null; needsReconnect: boolean };
  apple: { connected: boolean; email: string | null };
}

export async function getConnectionStatus(userId: string): Promise<ConnectionStatus> {
  const { data } = await supabaseAdmin
    .from("user_calendar_connections")
    .select("provider, apple_email, google_email, google_token_expires_at")
    .eq("user_id", userId);

  const google = (data ?? []).find((r: any) => r.provider === "google");
  const apple = (data ?? []).find((r: any) => r.provider === "apple");

  return {
    google: {
      connected: !!google,
      email: google?.google_email ?? null,
      needsReconnect:
        !!google &&
        !!google.google_token_expires_at &&
        new Date(google.google_token_expires_at) < new Date(),
    },
    apple: { connected: !!apple, email: apple?.apple_email ?? null },
  };
}

export async function disconnectProvider(userId: string, provider: "google" | "apple") {
  const { error } = await supabaseAdmin
    .from("user_calendar_connections")
    .delete()
    .eq("user_id", userId)
    .eq("provider", provider);
  if (error) throw new Error(error.message);
}

export async function connectApple(userId: string, appleEmail: string, appSpecificPassword: string) {
  await verifyAppleCredentials(appleEmail, appSpecificPassword); // throws on bad creds
  const encrypted = encryptSecret(appSpecificPassword);
  const { error } = await supabaseAdmin.from("user_calendar_connections").upsert(
    {
      user_id: userId,
      provider: "apple",
      apple_email: appleEmail,
      encrypted_password: encrypted,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,provider" }
  );
  if (error) throw new Error(error.message);
}

export async function connectGoogle(userId: string, refreshToken: string, accessToken: string) {
  const email = await fetchGoogleEmail(accessToken);
  // Google's 7-day refresh-token lifetime for apps still in "Testing"
  // publishing status -- see the migration file's comment. We can't extend
  // this without going through Google's app verification, which is
  // explicitly out of scope for the private beta.
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const { error } = await supabaseAdmin.from("user_calendar_connections").upsert(
    {
      user_id: userId,
      provider: "google",
      google_email: email,
      encrypted_refresh_token: encryptSecret(refreshToken),
      google_token_expires_at: expiresAt,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,provider" }
  );
  if (error) throw new Error(error.message);
}

/** Returns a live access token, or null if not connected / needs reconnecting. */
async function getValidGoogleAccessToken(userId: string): Promise<string | null> {
  const { data } = await supabaseAdmin
    .from("user_calendar_connections")
    .select("encrypted_refresh_token")
    .eq("user_id", userId)
    .eq("provider", "google")
    .maybeSingle();
  if (!data?.encrypted_refresh_token) return null;
  try {
    const refreshToken = decryptSecret(data.encrypted_refresh_token);
    const { accessToken } = await refreshAccessToken(refreshToken);
    return accessToken;
  } catch {
    return null;
  }
}

export interface DayCalendarData {
  google: string[]; // event titles that day
  apple: string[];
  rlgl: { status: "red" | "yellow" | "green" | "unresponded" | null; sessionTitles: string[] };
}

function dateKeyInTz(iso: string, tz: string): string {
  try {
    // en-CA formats as YYYY-MM-DD, which is exactly the bucket key we want.
    return new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date(iso));
  } catch {
    return iso.slice(0, 10);
  }
}

function bucketEventsByDay(events: CalEvent[], tz: string): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  events.forEach((e) => {
    const key = dateKeyInTz(e.start, tz);
    if (!out[key]) out[key] = [];
    out[key].push(e.title);
  });
  return out;
}

/**
 * Merges this user's connected Google/Apple calendars with every RLGL
 * session commitment they have (across every band they're in), for the
 * given date range. Returns a map keyed by "YYYY-MM-DD".
 */
export async function fetchMonthData(
  userId: string,
  startDateISO: string,
  endDateISO: string,
  tz: string
): Promise<Record<string, DayCalendarData>> {
  const result: Record<string, DayCalendarData> = {};
  const ensure = (key: string): DayCalendarData => {
    if (!result[key]) result[key] = { google: [], apple: [], rlgl: { status: null, sessionTitles: [] } };
    return result[key];
  };

  const timeMin = new Date(`${startDateISO}T00:00:00Z`).toISOString();
  const maxDate = new Date(`${endDateISO}T00:00:00Z`);
  maxDate.setUTCDate(maxDate.getUTCDate() + 1);
  const timeMax = maxDate.toISOString();

  // --- Google ---
  const accessToken = await getValidGoogleAccessToken(userId);
  if (accessToken) {
    try {
      const events = await fetchGoogleEvents(accessToken, timeMin, timeMax, tz);
      const byDay = bucketEventsByDay(events, tz);
      Object.entries(byDay).forEach(([day, titles]) => (ensure(day).google = titles));
    } catch {
      // Stale/broken token -- surfaced via getConnectionStatus's
      // needsReconnect flag, not treated as fatal here.
    }
  }

  // --- Apple ---
  const { data: appleCred } = await supabaseAdmin
    .from("user_calendar_connections")
    .select("apple_email, encrypted_password")
    .eq("user_id", userId)
    .eq("provider", "apple")
    .maybeSingle();
  if (appleCred?.encrypted_password) {
    try {
      const pw = decryptSecret(appleCred.encrypted_password);
      const events = await fetchAppleEvents(appleCred.apple_email, pw, timeMin, timeMax);
      const byDay = bucketEventsByDay(events, tz);
      Object.entries(byDay).forEach(([day, titles]) => (ensure(day).apple = titles));
    } catch {
      // Credential revoked -- ignore for this pass; the person has to
      // explicitly reconnect from the My Calendar page to clear this.
    }
  }

  // --- RLGL commitments across every band this person is a member of ---
  const { data: memberships } = await supabaseAdmin
    .from("members")
    .select("id, band_id")
    .eq("user_id", userId);

  const bandIds = (memberships ?? []).map((m: any) => m.band_id);
  const memberIdByBand: Record<string, string> = {};
  (memberships ?? []).forEach((m: any) => (memberIdByBand[m.band_id] = m.id));

  if (bandIds.length > 0) {
    const { data: sessions } = await supabaseAdmin
      .from("sessions")
      .select("id, band_id, title, start_date, end_date, active_weekdays")
      .in("band_id", bandIds)
      .lte("start_date", endDateISO)
      .gte("end_date", startDateISO);

    const dayStatusSets: Record<string, Set<string>> = {};

    for (const session of sessions ?? []) {
      const memberId = memberIdByBand[session.band_id];
      if (!memberId) continue;
      const activeWeekdays: number[] = session.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];
      const dates = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);

      const { data: avail } = await supabaseAdmin
        .from("availability")
        .select("day_index, status")
        .eq("session_id", session.id)
        .eq("member_id", memberId);

      const statusByDayIndex: Record<number, string[]> = {};
      (avail ?? []).forEach((a: any) => {
        if (!statusByDayIndex[a.day_index]) statusByDayIndex[a.day_index] = [];
        statusByDayIndex[a.day_index].push(a.status);
      });

      dates.forEach((date, day_index) => {
        if (date < startDateISO || date > endDateISO) return;
        const day = ensure(date);
        day.rlgl.sessionTitles.push(session.title);
        if (!dayStatusSets[date]) dayStatusSets[date] = new Set();
        (statusByDayIndex[day_index] ?? []).forEach((s) => dayStatusSets[date].add(s));
      });
    }

    Object.entries(result).forEach(([date, day]) => {
      if (day.rlgl.sessionTitles.length === 0) return;
      const set = dayStatusSets[date];
      if (set?.has("red")) day.rlgl.status = "red";
      else if (set?.has("yellow")) day.rlgl.status = "yellow";
      else if (set?.has("green")) day.rlgl.status = "green";
      else day.rlgl.status = "unresponded";
    });
  }

  return result;
}
