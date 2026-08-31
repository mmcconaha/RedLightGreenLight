// Apple/iCloud calendar sync via CalDAV. Apple has no OAuth API for this —
// authentication is HTTP Basic Auth against caldav.icloud.com using the
// user's Apple ID email + an app-specific password they generate themselves
// at appleid.apple.com (their real Apple ID password is never accepted here,
// by Apple's own design). tsdav handles the CalDAV principal/calendar-home
// discovery (iCloud accounts live behind per-account hosts like
// p67-caldav.icloud.com — tsdav's client.login() resolves that
// transparently instead of us hand-rolling the PROPFIND dance).
import { DAVClient } from "tsdav";
import ical from "node-ical";
import type { CalEvent } from "./calendarMatch";

async function makeClient(appleEmail: string, appSpecificPassword: string) {
  const client = new DAVClient({
    serverUrl: "https://caldav.icloud.com",
    credentials: { username: appleEmail, password: appSpecificPassword },
    authMethod: "Basic",
    defaultAccountType: "caldav",
  });
  await client.login();
  return client;
}

/** Throws if the email/app-specific password can't authenticate. */
export async function verifyAppleCredentials(
  appleEmail: string,
  appSpecificPassword: string
): Promise<void> {
  const client = await makeClient(appleEmail, appSpecificPassword);
  await client.fetchCalendars();
}

export async function fetchAppleEvents(
  appleEmail: string,
  appSpecificPassword: string,
  timeMinISO: string,
  timeMaxISO: string
): Promise<CalEvent[]> {
  const client = await makeClient(appleEmail, appSpecificPassword);
  const calendars = await client.fetchCalendars();

  const events: CalEvent[] = [];

  for (const calendar of calendars) {
    let objects: Awaited<ReturnType<typeof client.fetchCalendarObjects>>;
    try {
      objects = await client.fetchCalendarObjects({
        calendar,
        timeRange: { start: timeMinISO, end: timeMaxISO },
      });
    } catch {
      // Some calendars (e.g. subscribed read-only holiday/birthday
      // calendars) can reject a time-range query independently of the
      // others — skip that one calendar rather than aborting the whole
      // sync over it.
      continue;
    }

    for (const obj of objects) {
      if (!obj.data) continue;
      let parsed: ReturnType<typeof ical.sync.parseICS>;
      try {
        parsed = ical.sync.parseICS(obj.data);
      } catch {
        continue;
      }
      for (const key in parsed) {
        const comp = parsed[key] as any;
        if (comp.type !== "VEVENT") continue;
        if (!comp.start || !comp.end) continue;
        const start = new Date(comp.start);
        const end = new Date(comp.end);
        if (isNaN(start.getTime()) || isNaN(end.getTime())) continue;
        events.push({
          title: comp.summary || "(untitled event)",
          start: start.toISOString(),
          end: end.toISOString(),
        });
      }
    }
  }

  return events;
}
