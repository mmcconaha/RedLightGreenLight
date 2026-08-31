// Shared calendar-matching logic — used by both the Google Calendar sync
// (lib/google.ts) and the Apple/iCloud CalDAV sync (lib/apple.ts). Neither
// provider's specifics belong here: this file only knows about the generic
// shape of "an event with a title, start, and end" and how to line those up
// against a session's date/hour blocks in a given timezone.

export interface CalEvent {
  title: string;
  start: string;
  end: string;
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
  if (isNaN(date.getTime())) return 0;
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
  let h = Number.isFinite(hour) ? hour : 0;
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
