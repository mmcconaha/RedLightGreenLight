#!/bin/bash
set -e
cat > "app/api/auth/google/callback/route.ts" << 'CALLBACK_EOF'
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
CALLBACK_EOF
cat > "app/session/[id]/respond/page.tsx" << 'RESPOND_EOF'
"use client";

import { useEffect, useState, useRef } from "react";
import { supabase } from "@/lib/supabase";
import { Status } from "@/lib/types";
import { dateRangeFiltered } from "@/lib/dates";
import { InteractivePaintCalendar, BlockDef, SIMPLE_BLOCKS, cellKey } from "@/components/Calendar";

export default function RespondPage({ params }: { params: { id: string } }) {
  const [checkingSession, setCheckingSession] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState("");

  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [blocks, setBlocks] = useState<BlockDef[]>([]);
  const [dates, setDates] = useState<string[]>([]);
  const [statuses, setStatuses] = useState<Record<string, Status>>({});
  const [loadError, setLoadError] = useState("");
  const [justSynced, setJustSynced] = useState<string | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [eventContext, setEventContext] = useState<Record<string, string[]>>({});
  const [saveState, setSaveState] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const loadExisting = async (memberIdArg: string, dateList: string[]) => {
    const { data: existing } = await supabase
      .from("availability")
      .select("day_index, block_index, status")
      .eq("session_id", params.id)
      .eq("member_id", memberIdArg);
    if (existing && existing.length > 0) {
      const pre: Record<string, Status> = {};
      existing.forEach((r) => {
        const date = dateList[r.day_index];
        if (date) pre[cellKey(date, r.block_index)] = r.status as Status;
      });
      setStatuses(pre);
    }
  };

  const loadNotes = async (memberIdArg: string, dateList: string[]) => {
    const { data: notes } = await supabase
      .from("private_notes")
      .select("day_index, block_index, titles")
      .eq("session_id", params.id)
      .eq("member_id", memberIdArg);
    if (notes && notes.length > 0) {
      const ctx: Record<string, string[]> = {};
      notes.forEach((n) => {
        const date = dateList[n.day_index];
        if (date) ctx[cellKey(date, n.block_index)] = n.titles as string[];
      });
      setEventContext(ctx);
    }
  };

  useEffect(() => {
    const load = async () => {
      const { data: session, error: sessionError } = await supabase
        .from("sessions")
        .select("start_date, end_date, blocks, active_weekdays")
        .eq("id", params.id)
        .single();

      if (sessionError || !session?.start_date || !session?.end_date) {
        setLoadError(
          "This session doesn't have a date range set up yet — ask whoever's organizing to add one."
        );
        setCheckingSession(false);
        return;
      }

      setStartDate(session.start_date);
      setEndDate(session.end_date);
      const rawBlocks = session.blocks;
      const isValid =
        Array.isArray(rawBlocks) &&
        rawBlocks.length > 0 &&
        rawBlocks.every(
          (x: any) => x && typeof x.label === "string" && typeof x.start_hour === "number" && typeof x.end_hour === "number"
        );
      const sessionBlocks: BlockDef[] = isValid ? rawBlocks : SIMPLE_BLOCKS;
      setBlocks(sessionBlocks);
      const activeWeekdays: number[] = session.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];
      const d = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
      setDates(d);

      const { data } = await supabase.auth.getSession();
      if (data.session) {
        const { data: member } = await supabase
          .from("members")
          .select("id, name")
          .eq("user_id", data.session.user.id)
          .single();
        if (member) {
          setMemberId(member.id);
          setMemberName(member.name);
          await loadExisting(member.id, d);
          await loadNotes(member.id, d);
        }
      }

      const params2 = new URLSearchParams(window.location.search);
      if (params2.get("synced") === "1") {
        const rowsCount = params2.get("rows");
        const eventsCount = params2.get("events");
        const sample = params2.get("sample");
        const overlap = params2.get("overlap");
        let msg = `Synced — Google returned ${eventsCount ?? "?"} events, ${rowsCount ?? "some"} time slots marked red below.`;
        if (sample) msg += ` Raw event(s): ${decodeURIComponent(sample)}`;
        if (overlap) msg += ` || Overlap check: ${decodeURIComponent(overlap)}`;
        setJustSynced(msg);
        window.history.replaceState({}, "", window.location.pathname);
      }
      if (params2.get("sync_error") === "1") {
        const detail = params2.get("detail");
        setSyncError(detail ? decodeURIComponent(detail) : "Something went wrong syncing your calendar.");
      }
      const noteErrParam = params2.get("note_error");
      if (noteErrParam) {
        setSyncError(`Colors synced, but saving the "why" notes failed: ${decodeURIComponent(noteErrParam)}`);
      }

      setCheckingSession(false);
    };
    load();
  }, [params.id]);

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password, or ask whoever set this up.");
      return;
    }
    const { data: member } = await supabase
      .from("members")
      .select("id, name")
      .eq("user_id", data.user.id)
      .single();
    if (!member) {
      setLoginError("Logged in, but no member profile found for this band yet.");
      return;
    }
    setMemberId(member.id);
    setMemberName(member.name);
    await loadExisting(member.id, dates);
    await loadNotes(member.id, dates);
  };

  const connectGoogle = () => {
    if (!memberId) return;
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    window.location.href = `/api/auth/google/start?session=${params.id}&member=${memberId}&tz=${encodeURIComponent(tz)}`;
  };

  const saveAll = async (currentStatuses: Record<string, Status>) => {
    if (!memberId) return;
    setSaveState("saving");

    const upsertRows: any[] = [];
    const clearKeys: { day_index: number; block_index: number }[] = [];

    dates.forEach((date, day_index) => {
      blocks.forEach((_, block_index) => {
        const status = currentStatuses[cellKey(date, block_index)];
        if (status && status !== "unset") {
          upsertRows.push({
            session_id: params.id,
            member_id: memberId,
            day_index,
            block_index,
            status,
          });
        } else {
          clearKeys.push({ day_index, block_index });
        }
      });
    });

    let ok = true;
    if (upsertRows.length > 0) {
      const { error } = await supabase
        .from("availability")
        .upsert(upsertRows, { onConflict: "session_id,member_id,day_index,block_index" });
      if (error) ok = false;
    }
    // Clear out any cells the person painted back to "unset" so a
    // changed mind actually removes the old answer instead of leaving
    // a stale row behind.
    for (const k of clearKeys) {
      const { error } = await supabase
        .from("availability")
        .delete()
        .eq("session_id", params.id)
        .eq("member_id", memberId)
        .eq("day_index", k.day_index)
        .eq("block_index", k.block_index);
      if (error) ok = false;
    }

    setSaveState(ok ? "saved" : "error");
  };

  const handlePaint = (date: string, block: number, value: Status) => {
    setStatuses((prev) => {
      const next = { ...prev, [cellKey(date, block)]: value };
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      saveTimerRef.current = setTimeout(() => saveAll(next), 700);
      return next;
    });
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <div className="flex gap-2 mb-2">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-3xl font-black uppercase tracking-tight leading-none mb-2">
          Red Light
          <br />
          Green Light
        </h1>
        <p className="text-sm text-gray-400 mb-5 max-w-md">
          Click a day to color it, drag to paint more. No calendar app, no explaining, no guilt.
        </p>

        <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3 text-sm text-gray-300 mb-6 flex gap-2">
          <span>🔒</span>
          <span>
            Nobody sees your reasons — only red, yellow, or green. If you sync your calendar, event
            names are shown only to you on this screen so you have context to adjust things — they
            are never saved and never shown to anyone else.
          </span>
        </div>

        {loadError ? (
          <p className="text-[#FF5A5F] text-sm">{loadError}</p>
        ) : checkingSession ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : !memberId ? (
          <div>
            <input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Email"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            <input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              placeholder="Password"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            {loginError && <p className="text-[#FF5A5F] text-xs mb-3">{loginError}</p>}
            <button
              onClick={login}
              className="w-full py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              Log in
            </button>
          </div>
        ) : (
          <>
            <p className="text-sm text-gray-300 mb-3">Hey {memberName} —</p>

            {syncError && (
              <div className="bg-[#2A1616] border border-[#FF5A5F] rounded-lg p-3 text-sm text-[#FF5A5F] mb-4">
                Sync failed: {syncError}
              </div>
            )}

            {justSynced && (
              <div className="bg-[#1C2A22] border border-[#35D07F] rounded-lg p-3 text-sm text-[#35D07F] mb-4">
                {justSynced}
              </div>
            )}

            {Object.keys(eventContext).length > 0 && (
              <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg p-3 mb-4">
                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                  What's blocking these (only you can see this)
                </div>
                <div className="space-y-1.5 max-h-48 overflow-y-auto">
                  {Object.entries(eventContext).map(([key, titles]) => {
                    const [date, blockStr] = key.split("|");
                    const block = Number(blockStr);
                    const label = blocks[block]?.label ?? `Block ${block}`;
                    const d = new Date(date + "T00:00:00");
                    const short = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
                    return (
                      <div key={key} className="text-xs text-gray-300">
                        <span className="font-bold">{short} {label}:</span> {titles.join(", ")}
                      </div>
                    );
                  })}
                </div>
                <div className="text-[11px] text-gray-500 mt-2">
                  If any of these can move, click that day above to change it from red.
                </div>
              </div>
            )}

            <button
              onClick={connectGoogle}
              className="w-full mb-4 py-2.5 rounded-lg border text-sm font-bold"
              style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#C7C9D1" }}
            >
              📅 Auto-fill from Google Calendar
            </button>

            <InteractivePaintCalendar
              startDate={startDate}
              endDate={endDate}
              dates={dates}
              blocks={blocks}
              statuses={statuses}
              eventContext={eventContext}
              onPaint={handlePaint}
            />

            <div className="mt-3 text-center text-xs" style={{ color: saveState === "error" ? "#FF5A5F" : "#8B8E98" }}>
              {saveState === "idle" && "Tap or drag any day — it saves automatically."}
              {saveState === "saving" && "Saving…"}
              {saveState === "saved" && "✓ Saved — come back anytime to change your answers."}
              {saveState === "error" && "Couldn't save that last change — try again."}
            </div>
          </>
        )}
      </div>
    </main>
  );
}
RESPOND_EOF
cat > "app/session/[id]/organizer/page.tsx" << 'ORG_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { dateRangeFiltered, formatFullDate } from "@/lib/dates";
import { SummaryPaintCalendar, BlockDef, SIMPLE_BLOCKS, cellKey } from "@/components/Calendar";

interface Suggestion {
  date: string;
  block: number;
  blurb: string;
}

export default function OrganizerPage({ params }: { params: { id: string } }) {
  const [checkingAuth, setCheckingAuth] = useState(true);
  const [authorized, setAuthorized] = useState(false);
  const [authError, setAuthError] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");

  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [blocks, setBlocks] = useState<BlockDef[]>([]);
  const [dates, setDates] = useState<string[]>([]);
  const [counts, setCounts] = useState<Record<string, { green: number; yellow: number; red: number }>>({});
  const [total, setTotal] = useState(0);
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");

  const checkOwnership = async (userId: string, bandId: string) => {
    const { data: band } = await supabase
      .from("bands")
      .select("id")
      .eq("id", bandId)
      .eq("owner_id", userId)
      .single();
    return !!band;
  };

  const loadSessionData = async (bandId: string) => {
    const { data: session, error: sessionError } = await supabase
      .from("sessions")
      .select("start_date, end_date, blocks, active_weekdays")
      .eq("id", params.id)
      .single();

    if (sessionError || !session?.start_date || !session?.end_date) {
      setLoadError("This session doesn't have a date range set up yet.");
      setLoading(false);
      return;
    }

    setStartDate(session.start_date);
    setEndDate(session.end_date);
    const rawBlocks = session.blocks;
    const isValid =
      Array.isArray(rawBlocks) &&
      rawBlocks.length > 0 &&
      rawBlocks.every(
        (x: any) => x && typeof x.label === "string" && typeof x.start_hour === "number" && typeof x.end_hour === "number"
      );
    const sessionBlocks: BlockDef[] = isValid ? rawBlocks : SIMPLE_BLOCKS;
    setBlocks(sessionBlocks);
    const activeWeekdays: number[] = session.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];
    const d = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
    setDates(d);

    const res = await fetch(`/api/session/${params.id}/suggest`);
    const json = await res.json();

    const grouped: Record<string, { green: number; yellow: number; red: number }> = {};
    let max = 0;
    (json.allCounts ?? []).forEach((c: any) => {
      const date = d[c.day_index];
      if (date) {
        grouped[cellKey(date, c.block_index)] = c;
        max = Math.max(max, c.responded);
      }
    });
    setCounts(grouped);
    setTotal(max);
    setSuggestions(
      (json.suggestions ?? []).map((s: any) => ({
        date: d[s.day_index],
        block: s.block_index,
        blurb: s.blurb,
      }))
    );
    setLoading(false);
  };

  useEffect(() => {
    const init = async () => {
      const { data: session } = await supabase
        .from("sessions")
        .select("band_id")
        .eq("id", params.id)
        .single();

      if (!session?.band_id) {
        setAuthError("This session doesn't exist.");
        setCheckingAuth(false);
        return;
      }

      const { data: authData } = await supabase.auth.getSession();
      if (authData.session) {
        const owns = await checkOwnership(authData.session.user.id, session.band_id);
        if (owns) {
          setAuthorized(true);
          await loadSessionData(session.band_id);
        } else {
          setAuthError("You're not the organizer for this band's sessions.");
        }
      }
      setCheckingAuth(false);
    };
    init();
  }, [params.id]);

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password.");
      return;
    }
    const { data: session } = await supabase
      .from("sessions")
      .select("band_id")
      .eq("id", params.id)
      .single();
    if (!session?.band_id) {
      setAuthError("This session doesn't exist.");
      return;
    }
    const owns = await checkOwnership(data.user.id, session.band_id);
    if (!owns) {
      setAuthError("You're not the organizer for this band's sessions.");
      return;
    }
    setAuthorized(true);
    setLoading(true);
    await loadSessionData(session.band_id);
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <h1 className="text-2xl font-black uppercase mb-1">Group view</h1>
        <p className="text-sm text-gray-400 mb-6">
          Darker green = more people free. Nobody's individual answer is shown here.
        </p>

        {checkingAuth ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : !authorized ? (
          <div>
            {authError && <p className="text-[#FF5A5F] text-sm mb-3">{authError}</p>}
            <p className="text-sm text-gray-400 mb-3">Log in as the organizer to see this.</p>
            <input
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Email"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            <input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              placeholder="Password"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            {loginError && <p className="text-[#FF5A5F] text-xs mb-3">{loginError}</p>}
            <button
              onClick={login}
              className="w-full py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              Log in
            </button>
          </div>
        ) : loadError ? (
          <p className="text-[#FF5A5F] text-sm">{loadError}</p>
        ) : loading ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : (
          <>
            <div className="mb-7">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                Suggested windows
              </div>
              {suggestions.length === 0 ? (
                <p className="text-sm text-gray-400">No clean windows yet — need a few more responses.</p>
              ) : (
                suggestions.map((s) => (
                  <div
                    key={`${s.date}-${s.block}`}
                    className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl px-3.5 py-3 mb-2 flex justify-between items-center"
                  >
                    <div>
                      <div className="font-bold text-sm">
                        {formatFullDate(s.date)} — {blocks[s.block]?.label ?? ""}
                      </div>
                      <div className="text-xs text-gray-400 mt-0.5">{s.blurb}</div>
                    </div>
                    <div
                      className="rounded-full flex-shrink-0"
                      style={{ width: 26, height: 26, background: "#35D07F", boxShadow: "0 0 10px #35D07F88" }}
                    />
                  </div>
                ))
              )}
            </div>

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">Calendar</div>
            <SummaryPaintCalendar startDate={startDate} endDate={endDate} dates={dates} blocks={blocks} counts={counts} total={total} />
          </>
        )}
      </div>
    </main>
  );
}
ORG_EOF
echo done
