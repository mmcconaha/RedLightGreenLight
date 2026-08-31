import { NextResponse } from "next/server";
import { exchangeCode, fetchEvents, eventsForRange, zonedTimeToUtc } from "@/lib/google";
import { supabase } from "@/lib/supabase";
import { supabaseAdmin } from "@/lib/supabaseAdmin";
import { dateRangeFiltered } from "@/lib/dates";
import { BlockDef, SIMPLE_BLOCKS } from "@/components/Calendar";

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

    function isValidBlocks(b: any): b is BlockDef[] {
      return (
        Array.isArray(b) &&
        b.length > 0 &&
        b.every(
          (x: any) =>
            x &&
            typeof x.label === "string" &&
            typeof x.start_hour === "number" &&
            typeof x.end_hour === "number"
        )
      );
    }
    const blocks: BlockDef[] = isValidBlocks(session.blocks) ? session.blocks : SIMPLE_BLOCKS;
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

    let overlapDebug = "";
    if (events.length > 0) {
      const firstEventDate = events[0].start.slice(0, 10);
      const checks = blocks.map((b) => {
        const titles = eventsForRange(firstEventDate, b.start_hour, b.end_hour, tz, events);
        return `${b.label}(${b.start_hour}-${b.end_hour})=${titles.length > 0 ? "MATCH" : "no"}`;
      });
      overlapDebug = `date=${firstEventDate} tz=${tz} ${checks.join(" ")}`;
    }
    const overlapParam = overlapDebug ? `&overlap=${encodeURIComponent(overlapDebug)}` : "";

    return NextResponse.redirect(
      new URL(
        `/session/${sessionId}/respond?synced=1&rows=${rows.length}&events=${events.length}${noteErrorParam}${sampleParam}${overlapParam}`,
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
