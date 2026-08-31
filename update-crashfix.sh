#!/bin/bash
set -e
echo "Writing OAuth callback route (crash-proofed)..."
cat > "app/api/auth/google/callback/route.ts" << 'CALLBACK_EOF'
import { NextResponse } from "next/server";
import { exchangeCode, fetchEvents, eventsForRange, zonedTimeToUtc } from "@/lib/google";
import { supabase } from "@/lib/supabase";
import { supabaseAdmin } from "@/lib/supabaseAdmin";
import { dateRangeFiltered } from "@/lib/dates";
import { BlockDef } from "@/components/Calendar";

export async function GET(req: Request) {
  const url = new URL(req.url);

  try {
    const code = url.searchParams.get("code");
    const stateRaw = url.searchParams.get("state");
    if (!code || !stateRaw) {
      return NextResponse.redirect(new URL("/", url.origin));
    }

    const { sessionId, memberId, tz } = JSON.parse(Buffer.from(stateRaw, "base64url").toString());

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

    const timeMin = new Date(session.start_date + "T00:00:00Z").toISOString();
    const timeMaxDate = new Date(session.end_date + "T00:00:00Z");
    timeMaxDate.setUTCDate(timeMaxDate.getUTCDate() + 1);
    const timeMax = timeMaxDate.toISOString();

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

    let boundaryDebug = "";
    try {
      if (events.length > 0) {
        const firstEventDate = events[0].start.slice(0, 10);
        const parts = blocks.map((b) => {
          const bs = zonedTimeToUtc(firstEventDate, b.start_hour, tz);
          const be = zonedTimeToUtc(firstEventDate, b.end_hour, tz);
          return `${b.label}[${bs.toISOString()} to ${be.toISOString()}]`;
        });
        boundaryDebug = `tz=${tz} date=${firstEventDate} blocks: ${parts.join(" ")}`;
      }
    } catch (e: any) {
      boundaryDebug = `debug_failed: ${e?.message || "unknown"}`;
    }
    const boundaryParam = boundaryDebug ? `&boundaries=${encodeURIComponent(boundaryDebug)}` : "";

    return NextResponse.redirect(
      new URL(
        `/session/${sessionId}/respond?synced=1&rows=${rows.length}&events=${events.length}${noteErrorParam}${sampleParam}${boundaryParam}`,
        url.origin
      )
    );
  } catch (e: any) {
    // Absolute last resort — never let this route produce a raw crash page.
    const msg = encodeURIComponent(e?.message || "unexpected error");
    return NextResponse.redirect(new URL(`/?crash=1&detail=${msg}`, url.origin));
  }
}
CALLBACK_EOF
echo "Done."
