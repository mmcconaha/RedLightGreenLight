"use client";

import { useEffect, useState, useRef } from "react";
import { supabase } from "@/lib/supabase";
import { Status } from "@/lib/types";
import { dateRangeFiltered } from "@/lib/dates";
import { InteractivePaintCalendar, BlockDef, SIMPLE_BLOCKS, cellKey } from "@/components/Calendar";
import { Bulletin } from "@/components/Bulletin";
import { FileShare } from "@/components/FileShare";
import { downloadIcs } from "@/lib/ics";
import AppNav from "@/components/AppNav";

export default function RespondPage({ params }: { params: { id: string } }) {
  const [checkingSession, setCheckingSession] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [magicLinkStatus, setMagicLinkStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [magicLinkError, setMagicLinkError] = useState("");
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState("");
  const [isOwner, setIsOwner] = useState(false);

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
  const [confirmedTitle, setConfirmedTitle] = useState<string | null>(null);
  const [confirmedStartUtc, setConfirmedStartUtc] = useState<string | null>(null);
  const [confirmedEndUtc, setConfirmedEndUtc] = useState<string | null>(null);

  const [appleConnected, setAppleConnected] = useState(false);
  const [appleEmailDisplay, setAppleEmailDisplay] = useState("");
  const [showAppleForm, setShowAppleForm] = useState(false);
  const [appleEmailInput, setAppleEmailInput] = useState("");
  const [applePasswordInput, setApplePasswordInput] = useState("");
  const [appleBusy, setAppleBusy] = useState(false);
  const [appleMsg, setAppleMsg] = useState<string | null>(null);

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

  const authenticateMember = async (uid: string) => {
    // Re-fetches this session's own date range rather than trusting outer
    // component state -- keeps this safe to call from the magic-link
    // listener below, which can fire well after the initial load.
    const { data: sessionRow } = await supabase
      .from("sessions")
      .select("band_id, start_date, end_date, active_weekdays")
      .eq("id", params.id)
      .single();
    if (!sessionRow?.start_date || !sessionRow?.end_date) return;
    const activeWeekdays: number[] = sessionRow.active_weekdays ?? [0, 1, 2, 3, 4, 5, 6];
    const d = dateRangeFiltered(sessionRow.start_date, sessionRow.end_date, activeWeekdays);

    const { data: member } = await supabase
      .from("members")
      .select("id, name")
      .eq("user_id", uid)
      .single();
    if (!member) return;
    setMemberId(member.id);
    setMemberName(member.name);
    await loadExisting(member.id, d);
    await loadNotes(member.id, d);
    await checkAppleStatus(member.id);

    if (sessionRow.band_id) {
      const { data: band } = await supabase
        .from("bands")
        .select("owner_id")
        .eq("id", sessionRow.band_id)
        .single();
      setIsOwner(band?.owner_id === uid);
    }
  };

  useEffect(() => {
    const load = async () => {
      const { data: session, error: sessionError } = await supabase
        .from("sessions")
        .select("band_id, start_date, end_date, blocks, active_weekdays, confirmed_title, confirmed_start_utc, confirmed_end_utc")
        .eq("id", params.id)
        .single();

      if (sessionError || !session?.start_date || !session?.end_date) {
        setLoadError(
          "This session doesn't have a date range set up yet — ask whoever's organizing to add one."
        );
        setCheckingSession(false);
        return;
      }

      setConfirmedTitle(session.confirmed_title ?? null);
      setConfirmedStartUtc(session.confirmed_start_utc ?? null);
      setConfirmedEndUtc(session.confirmed_end_utc ?? null);
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
        await authenticateMember(data.session.user.id);
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

    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_IN" && session?.user) {
        authenticateMember(session.user.id);
      }
    });
    return () => sub.subscription.unsubscribe();
  }, [params.id]);

  const sendMagicLink = async () => {
    setMagicLinkError("");
    if (!email) {
      setMagicLinkError("Enter your email first.");
      return;
    }
    setMagicLinkStatus("sending");
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.href.split("?")[0] },
    });
    if (error) {
      setMagicLinkStatus("error");
      setMagicLinkError(error.message);
    } else {
      setMagicLinkStatus("sent");
    }
  };

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
    await checkAppleStatus(member.id);

    const { data: sessionRow } = await supabase
      .from("sessions")
      .select("band_id")
      .eq("id", params.id)
      .single();
    if (sessionRow?.band_id) {
      const { data: band } = await supabase
        .from("bands")
        .select("owner_id")
        .eq("id", sessionRow.band_id)
        .single();
      setIsOwner(band?.owner_id === data.user.id);
    }
  };

  const checkAppleStatus = async (memberIdArg: string) => {
    try {
      const res = await fetch(`/api/apple/status?memberId=${memberIdArg}`);
      const json = await res.json();
      setAppleConnected(!!json.connected);
      setAppleEmailDisplay(json.appleEmail || "");
    } catch {
      // Non-fatal — Apple section just stays in its "not connected" state.
    }
  };

  const connectApple = async () => {
    if (!memberId) return;
    setAppleMsg(null);
    if (!appleEmailInput || !applePasswordInput) {
      setAppleMsg("Enter your Apple ID email and an app-specific password.");
      return;
    }
    setAppleBusy(true);
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    try {
      const res = await fetch("/api/apple/connect", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          memberId,
          appleEmail: appleEmailInput,
          appSpecificPassword: applePasswordInput,
          sessionId: params.id,
          tz,
        }),
      });
      const json = await res.json();
      if (!json.ok) {
        setAppleMsg(json.error || "Couldn't connect Apple Calendar.");
        setAppleBusy(false);
        return;
      }
      setAppleConnected(true);
      setAppleEmailDisplay(appleEmailInput);
      setApplePasswordInput("");
      setShowAppleForm(false);
      if (json.sync?.ok) {
        setJustSynced(
          `Synced — Apple Calendar returned ${json.sync.events ?? "?"} events, ${json.sync.rows ?? "some"} time slots marked red below.`
        );
        await loadExisting(memberId, dates);
        await loadNotes(memberId, dates);
      } else if (json.sync?.error) {
        setAppleMsg(`Connected, but the first sync failed: ${json.sync.error}`);
      }
    } catch (e: any) {
      setAppleMsg(e?.message || "Couldn't connect Apple Calendar.");
    } finally {
      setAppleBusy(false);
    }
  };

  const syncApple = async () => {
    if (!memberId) return;
    setAppleBusy(true);
    setAppleMsg(null);
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    try {
      const res = await fetch(`/api/session/${params.id}/apple-sync`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ memberId, tz }),
      });
      const json = await res.json();
      if (json.ok) {
        setJustSynced(
          `Synced — Apple Calendar returned ${json.events ?? "?"} events, ${json.rows ?? "some"} time slots marked red below.`
        );
        await loadExisting(memberId, dates);
        await loadNotes(memberId, dates);
      } else {
        setAppleMsg(json.error || "Sync failed.");
      }
    } catch (e: any) {
      setAppleMsg(e?.message || "Sync failed.");
    } finally {
      setAppleBusy(false);
    }
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

        <AppNav current="respond" />

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

            <div className="flex items-center gap-2 my-4">
              <div className="flex-1 h-px bg-[#2C2F38]" />
              <span className="text-[11px] text-gray-500 font-bold">OR</span>
              <div className="flex-1 h-px bg-[#2C2F38]" />
            </div>

            {magicLinkStatus === "sent" ? (
              <p className="text-xs text-[#35D07F] text-center mb-3">
                Check your email — click the link to log in, no password needed.
              </p>
            ) : (
              <button
                onClick={sendMagicLink}
                disabled={magicLinkStatus === "sending"}
                className="w-full py-3 rounded-xl font-bold text-[15px]"
                style={{ background: "#1C1E24", color: "#F2F1EA", border: "1px solid #2C2F38" }}
              >
                {magicLinkStatus === "sending" ? "Sending…" : "✉️ Email me a login link"}
              </button>
            )}
            {magicLinkError && <p className="text-[#FF5A5F] text-xs mt-2">{magicLinkError}</p>}
          </div>
        ) : (
          <>
            <p className="text-sm text-gray-300 mb-3">Hey {memberName} —</p>

            {isOwner && (
              <a
                href={`/session/${params.id}/organizer`}
                className="block w-full text-center py-2.5 rounded-lg text-sm font-bold mb-5"
                style={{ background: "#1C1E24", color: "#F2F1EA", border: "1px solid #35D07F" }}
              >
                📋 Organizer view (see everyone's responses)
              </a>
            )}

            <Bulletin sessionId={params.id} authorName={memberName} />
            <FileShare sessionId={params.id} canUpload={false} />

            {confirmedTitle && confirmedStartUtc && confirmedEndUtc && (
              <div className="bg-[#1C2A22] border border-[#35D07F] rounded-xl p-3.5 mb-5">
                <div className="text-xs font-bold uppercase tracking-wide text-[#35D07F] mb-1">
                  Confirmed
                </div>
                <div className="font-bold text-sm mb-0.5">{confirmedTitle}</div>
                <div className="text-xs text-gray-300 mb-3">
                  {new Date(confirmedStartUtc).toLocaleString("en-US", {
                    weekday: "long",
                    month: "long",
                    day: "numeric",
                    hour: "numeric",
                    minute: "2-digit",
                  })}{" "}
                  –{" "}
                  {new Date(confirmedEndUtc).toLocaleString("en-US", { hour: "numeric", minute: "2-digit" })}
                </div>
                <button
                  onClick={() =>
                    downloadIcs(`${confirmedTitle}.ics`, confirmedTitle, confirmedStartUtc, confirmedEndUtc)
                  }
                  className="w-full py-2 rounded-lg text-sm font-bold"
                  style={{ background: "#35D07F", color: "#0E1712" }}
                >
                  Download calendar invite (.ics)
                </button>
              </div>
            )}

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

            {appleConnected ? (
              <div className="mb-4">
                <button
                  onClick={syncApple}
                  disabled={appleBusy}
                  className="w-full py-2.5 rounded-lg border text-sm font-bold"
                  style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#C7C9D1" }}
                >
                  {appleBusy ? "Syncing…" : ` Sync Apple Calendar (${appleEmailDisplay})`}
                </button>
                <button
                  onClick={() => setShowAppleForm(!showAppleForm)}
                  className="text-xs font-bold text-gray-500 mt-1.5"
                >
                  Use a different Apple ID
                </button>
                {showAppleForm && (
                  <div className="mt-2 bg-[#1C1E24] border border-[#2C2F38] rounded-lg p-3">
                    <input
                      value={appleEmailInput}
                      onChange={(e) => setAppleEmailInput(e.target.value)}
                      placeholder="Apple ID email"
                      className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm mb-2 outline-none"
                    />
                    <input
                      value={applePasswordInput}
                      onChange={(e) => setApplePasswordInput(e.target.value)}
                      type="password"
                      placeholder="App-specific password"
                      className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm mb-2 outline-none"
                    />
                    <button
                      onClick={connectApple}
                      disabled={appleBusy}
                      className="w-full py-2 rounded-lg text-sm font-bold"
                      style={{ background: "#35D07F", color: "#0E1712" }}
                    >
                      {appleBusy ? "Connecting…" : "Connect"}
                    </button>
                  </div>
                )}
                {appleMsg && <p className="text-xs text-gray-400 mt-2">{appleMsg}</p>}
              </div>
            ) : (
              <div className="mb-4">
                <button
                  onClick={() => setShowAppleForm(!showAppleForm)}
                  className="w-full py-2.5 rounded-lg border text-sm font-bold"
                  style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#C7C9D1" }}
                >
                  🍎 Auto-fill from Apple Calendar
                </button>
                {showAppleForm && (
                  <div className="mt-2 bg-[#1C1E24] border border-[#2C2F38] rounded-lg p-3">
                    <p className="text-xs text-gray-400 mb-2">
                      Use an{" "}
                      <a
                        href="https://support.apple.com/en-us/102654"
                        target="_blank"
                        rel="noreferrer"
                        className="underline"
                      >
                        app-specific password
                      </a>{" "}
                      — not your real Apple ID password. Apple won't accept your real one here anyway.
                    </p>
                    <input
                      value={appleEmailInput}
                      onChange={(e) => setAppleEmailInput(e.target.value)}
                      placeholder="Apple ID email"
                      className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm mb-2 outline-none"
                    />
                    <input
                      value={applePasswordInput}
                      onChange={(e) => setApplePasswordInput(e.target.value)}
                      type="password"
                      placeholder="App-specific password"
                      className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm mb-2 outline-none"
                    />
                    <button
                      onClick={connectApple}
                      disabled={appleBusy}
                      className="w-full py-2 rounded-lg text-sm font-bold"
                      style={{ background: "#35D07F", color: "#0E1712" }}
                    >
                      {appleBusy ? "Connecting…" : "Connect"}
                    </button>
                    {appleMsg && <p className="text-xs text-gray-400 mt-2">{appleMsg}</p>}
                  </div>
                )}
              </div>
            )}

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
