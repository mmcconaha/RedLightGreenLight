// Shared by both app/api/apple/connect (first-time connect + immediate
// sync) and app/api/session/[id]/apple-sync (re-sync with already-stored
// credentials), so the "turn events into availability rows" logic exists
// in exactly one place — same pattern as the Google callback route, just
// factored into a function instead of living inline in a single GET
// redirect handler, since this needs to be called from two different
// routes that each return JSON rather than redirect.
import { supabase } from "./supabase";
import { supabaseAdmin } from "./supabaseAdmin";
import { dateRangeFiltered } from "./dates";
import { BlockDef, SIMPLE_BLOCKS } from "@/components/Calendar";
import { eventsForRange } from "./calendarMatch";
import { fetchAppleEvents } from "./apple";
import { decryptSecret } from "./appleCrypto";

export interface AppleSyncResult {
  ok: boolean;
  rows?: number;
  events?: number;
  error?: string;
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

export async function runAppleSyncForSession(
  sessionId: string,
  memberId: string,
  tz: string
): Promise<AppleSyncResult> {
  const { data: cred } = await supabaseAdmin
    .from("apple_credentials")
    .select("apple_email, encrypted_password")
    .eq("member_id", memberId)
    .maybeSingle();

  if (!cred) {
    return { ok: false, error: "No Apple Calendar connected for this member yet." };
  }

  let appSpecificPassword: string;
  try {
    appSpecificPassword = decryptSecret(cred.encrypted_password);
  } catch (e: any) {
    return { ok: false, error: `Couldn't decrypt stored credential: ${e?.message || e}` };
  }

  const { data: session } = await supabase
    .from("sessions")
    .select("start_date, end_date, blocks, active_weekdays")
    .eq("id", sessionId)
    .single();

  if (!session?.start_date || !session?.end_date) {
    return { ok: false, error: "Session not found." };
  }

  const blocks: BlockDef[] = isValidBlocks(session.blocks) ? session.blocks : SIMPLE_BLOCKS;
  const activeWeekdays: number[] = session.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];

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
    return { ok: false, error: e?.message || "invalid session dates" };
  }

  let events;
  try {
    events = await fetchAppleEvents(cred.apple_email, appSpecificPassword, timeMin, timeMax);
  } catch (e: any) {
    return {
      ok: false,
      error:
        e?.message ||
        "Apple Calendar fetch failed — the app-specific password may have been revoked. Try reconnecting.",
    };
  }

  const dates = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
  const rows: any[] = [];
  const noteRows: any[] = [];

  dates.forEach((date, day_index) => {
    blocks.forEach((block, block_index) => {
      const titles = eventsForRange(date, block.start_hour, block.end_hour, tz, events);
      if (titles.length > 0) {
        rows.push({ session_id: sessionId, member_id: memberId, day_index, block_index, status: "red" });
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
    const { error } = await supabaseAdmin
      .from("availability")
      .upsert(rows, { onConflict: "session_id,member_id,day_index,block_index" });
    if (error) return { ok: false, error: error.message };
  }

  if (noteRows.length > 0) {
    // Not fatal if this fails — matches the Google sync flow, where the
    // colors are the part that has to succeed; the "why" notes are a bonus.
    await supabaseAdmin
      .from("private_notes")
      .upsert(noteRows, { onConflict: "session_id,member_id,day_index,block_index" });
  }

  return { ok: true, rows: rows.length, events: events.length };
}
