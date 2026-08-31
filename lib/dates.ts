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

// Full calendar weeks (Sun-Sat) covering the date range, including padding
// days from adjacent months so every week is a complete row of 7.
export function calendarWeeks(startISO: string, endISO: string): string[][] {
  const start = new Date(startISO + "T00:00:00");
  const end = new Date(endISO + "T00:00:00");
  const firstSunday = new Date(start);
  firstSunday.setDate(start.getDate() - start.getDay());
  const lastSaturday = new Date(end);
  lastSaturday.setDate(end.getDate() + (6 - end.getDay()));

  const weeks: string[][] = [];
  const cur = new Date(firstSunday);
  while (cur <= lastSaturday) {
    const week: string[] = [];
    for (let i = 0; i < 7; i++) {
      week.push(cur.toISOString().slice(0, 10));
      cur.setDate(cur.getDate() + 1);
    }
    weeks.push(week);
  }
  return weeks;
}

// Same as dateRange, but only includes dates whose weekday (0=Sun..6=Sat)
// is in activeWeekdays — lets an organizer exclude whole days of the week.
export function dateRangeFiltered(
  startISO: string,
  endISO: string,
  activeWeekdays: number[]
): string[] {
  return dateRange(startISO, endISO).filter((d) =>
    activeWeekdays.includes(new Date(d + "T00:00:00").getDay())
  );
}
