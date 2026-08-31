#!/bin/bash
set -e
echo "Writing lib/supabaseAdmin.ts..."
cat > "lib/supabaseAdmin.ts" << 'ADMIN_EOF'
import { createClient } from "@supabase/supabase-js";

// SERVER-ONLY client using the service role key — bypasses row-level
// security. Never import this into any "use client" file or expose
// SUPABASE_SERVICE_ROLE_KEY as NEXT_PUBLIC_. Used only in trusted
// server-side routes like the Google Calendar sync callback, where we
// need to write availability rows on behalf of the authenticated user
// without a browser session to carry their auth.uid().
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);
ADMIN_EOF
echo "Writing OAuth callback route..."
cat > "app/api/auth/google/callback/route.ts" << 'CALLBACK_EOF'
import { NextResponse } from "next/server";
import { exchangeCode, fetchFreeBusy, blockOverlapsBusy } from "@/lib/google";
import { supabase } from "@/lib/supabase";
import { supabaseAdmin } from "@/lib/supabaseAdmin";
import { dateRange } from "@/lib/dates";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const stateRaw = url.searchParams.get("state");
  if (!code || !stateRaw) {
    return NextResponse.redirect(new URL("/", url.origin));
  }

  const { sessionId, memberId, tz } = JSON.parse(Buffer.from(stateRaw, "base64url").toString());

  const { data: session } = await supabase
    .from("sessions")
    .select("start_date, end_date")
    .eq("id", sessionId)
    .single();

  if (!session?.start_date || !session?.end_date) {
    return NextResponse.redirect(new URL(`/session/${sessionId}/respond`, url.origin));
  }

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

  let busy;
  try {
    busy = await fetchFreeBusy(accessToken, timeMin, timeMax, tz);
  } catch (e: any) {
    const msg = encodeURIComponent(e?.message || "freebusy fetch failed");
    return NextResponse.redirect(
      new URL(`/session/${sessionId}/respond?sync_error=1&detail=${msg}`, url.origin)
    );
  }

  const dates = dateRange(session.start_date, session.end_date);
  const rows: any[] = [];
  dates.forEach((date, day_index) => {
    [0, 1, 2].forEach((block_index) => {
      if (blockOverlapsBusy(date, block_index, tz, busy)) {
        rows.push({
          session_id: sessionId,
          member_id: memberId,
          day_index,
          block_index,
          status: "red",
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

  return NextResponse.redirect(
    new URL(`/session/${sessionId}/respond?synced=1&busycount=${busy.length}&rows=${rows.length}`, url.origin)
  );
}
CALLBACK_EOF
echo "All files updated."
