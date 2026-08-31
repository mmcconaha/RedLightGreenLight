function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function fmtIcsUtc(iso: string): string {
  const d = new Date(iso);
  return (
    d.getUTCFullYear() +
    pad(d.getUTCMonth() + 1) +
    pad(d.getUTCDate()) +
    "T" +
    pad(d.getUTCHours()) +
    pad(d.getUTCMinutes()) +
    pad(d.getUTCSeconds()) +
    "Z"
  );
}

function escapeIcs(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/,/g, "\\,").replace(/;/g, "\\;").replace(/\n/g, "\\n");
}

export function buildIcs(title: string, startUtcIso: string, endUtcIso: string): string {
  const uid = `${Date.now()}-rlgl@redlightgreenlight`;
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Red Light Green Light//EN",
    "BEGIN:VEVENT",
    `UID:${uid}`,
    `DTSTAMP:${fmtIcsUtc(new Date().toISOString())}`,
    `DTSTART:${fmtIcsUtc(startUtcIso)}`,
    `DTEND:${fmtIcsUtc(endUtcIso)}`,
    `SUMMARY:${escapeIcs(title)}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lines.join("\r\n");
}

export function downloadIcs(filename: string, title: string, startUtcIso: string, endUtcIso: string) {
  const content = buildIcs(title, startUtcIso, endUtcIso);
  const blob = new Blob([content], { type: "text/calendar" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
