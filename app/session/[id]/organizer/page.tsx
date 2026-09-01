"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { dateRangeFiltered, formatFullDate } from "@/lib/dates";
import { InteractivePaintCalendar, SummaryPaintCalendar, BlockDef, SIMPLE_BLOCKS, cellKey } from "@/components/Calendar";
import { Status } from "@/lib/types";
import { zonedTimeToUtc } from "@/lib/google";
import { downloadIcs } from "@/lib/ics";
import { Bulletin } from "@/components/Bulletin";
import { FileShare } from "@/components/FileShare";
import AppNav from "@/components/AppNav";

interface Suggestion {
  date: string;
  block: number;
  blurb: string;
}

function formatHour(h: number): string {
  const period = h < 12 ? "AM" : "PM";
  let h12 = h % 12;
  if (h12 === 0) h12 = 12;
  return `${h12}:00 ${period}`;
}

export default function OrganizerPage({ params }: { params: { id: string } }) {
  const [checkingAuth, setCheckingAuth] = useState(true);
  const [authorized, setAuthorized] = useState(false);
  const [authError, setAuthError] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [magicLinkStatus, setMagicLinkStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [magicLinkError, setMagicLinkError] = useState("");
  const [ownerName, setOwnerName] = useState("Organizer");
  const [bandId, setBandId] = useState<string | null>(null);
  const [inviteCopied, setInviteCopied] = useState(false);
  const [inviteEmail, setInviteEmail] = useState("");
  const [invitePhone, setInvitePhone] = useState("");
  const [activeWeekdays, setActiveWeekdays] = useState<number[]>([0, 1, 2, 3, 4, 5, 6]);
  const [repeatTitle, setRepeatTitle] = useState("");
  const [repeatStartDate, setRepeatStartDate] = useState("");
  const [repeating, setRepeating] = useState(false);
  const [repeatError, setRepeatError] = useState("");

  const [sessionTitle, setSessionTitle] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [blocks, setBlocks] = useState<BlockDef[]>([]);
  const [dates, setDates] = useState<string[]>([]);
  const [counts, setCounts] = useState<Record<string, { green: number; yellow: number; red: number }>>({});
  const [total, setTotal] = useState(0);
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [members, setMembers] = useState<{ id: string; name: string }[]>([]);
  const [memberStatuses, setMemberStatuses] = useState<Record<string, Record<string, Status>>>({});
  const [expandedMember, setExpandedMember] = useState<string | null>(null);

  const [confirmedTitle, setConfirmedTitle] = useState<string | null>(null);
  const [confirmedStartUtc, setConfirmedStartUtc] = useState<string | null>(null);
  const [confirmedEndUtc, setConfirmedEndUtc] = useState<string | null>(null);

  const [pickDate, setPickDate] = useState("");
  const [pickStartHour, setPickStartHour] = useState(18);
  const [pickEndHour, setPickEndHour] = useState(21);
  const [pickTitle, setPickTitle] = useState("");
  const [confirming, setConfirming] = useState(false);

  const checkOwnership = async (userId: string, bandId: string) => {
    const { data: band } = await supabase
      .from("bands")
      .select("id")
      .eq("id", bandId)
      .eq("owner_id", userId)
      .single();
    return !!band;
  };

  const loadSessionData = async (bandId: string, userId: string) => {
    const { data: session, error: sessionError } = await supabase
      .from("sessions")
      .select("title, start_date, end_date, blocks, active_weekdays, confirmed_title, confirmed_start_utc, confirmed_end_utc")
      .eq("id", params.id)
      .single();

    if (sessionError || !session?.start_date || !session?.end_date) {
      setLoadError("This session doesn't have a date range set up yet.");
      setLoading(false);
      return;
    }

    setSessionTitle(session.title ?? "");
    setPickTitle(session.title ?? "");
    setStartDate(session.start_date);
    setEndDate(session.end_date);
    setConfirmedTitle(session.confirmed_title ?? null);
    setConfirmedStartUtc(session.confirmed_start_utc ?? null);
    setConfirmedEndUtc(session.confirmed_end_utc ?? null);

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
    setActiveWeekdays(activeWeekdays);
    const d = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
    setDates(d);
    if (d.length > 0) setPickDate(d[0]);

    // Default "repeat" suggestion: same title, one week later. Just a
    // starting point -- both fields are editable, since FBR repeats
    // constantly and Women In Harmony repeats rarely and irregularly.
    setRepeatTitle(session.title ?? "");
    const suggestedNext = new Date(session.start_date + "T00:00:00");
    suggestedNext.setDate(suggestedNext.getDate() + 7);
    setRepeatStartDate(suggestedNext.toISOString().slice(0, 10));

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

    // Individual responses — allowed by RLS for the band owner only.
    // Only colors are ever fetched here, never private_notes (event reasons).
    const { data: bandMembers } = await supabase
      .from("members")
      .select("id, name")
      .eq("band_id", bandId);
    setMembers(bandMembers ?? []);

    const { data: selfMember } = await supabase
      .from("members")
      .select("name")
      .eq("band_id", bandId)
      .eq("user_id", userId)
      .single();
    if (selfMember?.name) setOwnerName(selfMember.name);

    const { data: allAvailability } = await supabase
      .from("availability")
      .select("member_id, day_index, block_index, status")
      .eq("session_id", params.id);

    const perMember: Record<string, Record<string, Status>> = {};
    (allAvailability ?? []).forEach((row: any) => {
      const date = d[row.day_index];
      if (!date) return;
      if (!perMember[row.member_id]) perMember[row.member_id] = {};
      perMember[row.member_id][cellKey(date, row.block_index)] = row.status as Status;
    });
    setMemberStatuses(perMember);

    setLoading(false);
  };

  const authenticateAsOwner = async (uid: string) => {
    const { data: session } = await supabase
      .from("sessions")
      .select("band_id")
      .eq("id", params.id)
      .single();
    if (!session?.band_id) {
      setAuthError("This session doesn't exist.");
      return;
    }
    const owns = await checkOwnership(uid, session.band_id);
    if (!owns) {
      setAuthError("You're not the organizer for this band's sessions.");
      return;
    }
    setAuthorized(true);
    setBandId(session.band_id);
    setLoading(true);
    await loadSessionData(session.band_id, uid);
  };

  useEffect(() => {
    const init = async () => {
      const { data: authData } = await supabase.auth.getSession();
      if (authData.session) {
        await authenticateAsOwner(authData.session.user.id);
      }
      setCheckingAuth(false);
    };
    init();

    // Catches a magic link that finishes signing in just after this page has
    // already mounted.
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_IN" && session?.user) {
        authenticateAsOwner(session.user.id);
      }
    });
    return () => sub.subscription.unsubscribe();
  }, [params.id]);

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password.");
      return;
    }
    await authenticateAsOwner(data.user.id);
  };

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

  const confirmSession = async () => {
    if (!pickDate || !pickTitle.trim()) return;
    setConfirming(true);
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const startUtc = zonedTimeToUtc(pickDate, pickStartHour, tz).toISOString();
    const endUtc = zonedTimeToUtc(pickDate, pickEndHour, tz).toISOString();

    const { error } = await supabase
      .from("sessions")
      .update({
        confirmed_title: pickTitle.trim(),
        confirmed_start_utc: startUtc,
        confirmed_end_utc: endUtc,
      })
      .eq("id", params.id);

    setConfirming(false);
    if (!error) {
      setConfirmedTitle(pickTitle.trim());
      setConfirmedStartUtc(startUtc);
      setConfirmedEndUtc(endUtc);
    }
  };

  const inviteLink =
    bandId && typeof window !== "undefined"
      ? `${window.location.origin}/join/${bandId}?session=${params.id}`
      : "";

  const copyInviteLink = () => {
    if (!inviteLink) return;
    navigator.clipboard.writeText(inviteLink);
    setInviteCopied(true);
    setTimeout(() => setInviteCopied(false), 2000);
  };

  const inviteByEmail = () => {
    if (!inviteLink) return;
    const subject = encodeURIComponent(`Join us on RLGL for ${sessionTitle || "our next session"}`);
    const body = encodeURIComponent(
      `Hey! Tap this link to mark your availability for ${sessionTitle || "our next rehearsal"}:\n\n${inviteLink}`
    );
    const to = inviteEmail.trim() ? encodeURIComponent(inviteEmail.trim()) : "";
    window.location.href = `mailto:${to}?subject=${subject}&body=${body}`;
  };

  const inviteByText = () => {
    if (!inviteLink) return;
    const body = encodeURIComponent(
      `Join us on RLGL to mark your availability for ${sessionTitle || "our next rehearsal"}: ${inviteLink}`
    );
    const to = invitePhone.trim() ? invitePhone.trim().replace(/[^0-9+]/g, "") : "";
    // "?&body=" (not just "?body=" or "&body=") is the awkward but widely-cited
    // trick that works across both iOS's and Android's non-standard sms: URI
    // handling -- there's no single correct format for both platforms.
    window.location.href = `sms:${to}?&body=${body}`;
  };

  const duplicateSession = async () => {
    if (!repeatStartDate || !bandId) return;
    setRepeatError("");
    setRepeating(true);

    const spanDays = Math.round(
      (new Date(endDate + "T00:00:00").getTime() - new Date(startDate + "T00:00:00").getTime()) / 86400000
    );
    const newEnd = new Date(repeatStartDate + "T00:00:00");
    newEnd.setDate(newEnd.getDate() + spanDays);
    const newEndDate = newEnd.toISOString().slice(0, 10);

    const { data, error } = await supabase
      .from("sessions")
      .insert({
        band_id: bandId,
        title: repeatTitle.trim() || sessionTitle,
        start_date: repeatStartDate,
        end_date: newEndDate,
        mode: "custom",
        blocks,
        active_weekdays: activeWeekdays,
      })
      .select()
      .single();

    setRepeating(false);
    if (error || !data) {
      setRepeatError(error?.message || "Couldn't create the next session.");
      return;
    }
    window.location.href = `/session/${data.id}/organizer`;
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <h1 className="text-2xl font-black uppercase mb-1">Group view</h1>
        <p className="text-sm text-gray-400 mb-6">
          Darker green = more people free. Nobody's individual answer is shown here.
        </p>

        <AppNav current="organizer" />

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
        ) : loadError ? (
          <p className="text-[#FF5A5F] text-sm">{loadError}</p>
        ) : loading ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : (
          <>
            <h2 className="text-sm text-gray-400 mb-4">Welcome, {ownerName}</h2>

            <a
              href={`/session/${params.id}/respond`}
              className="block w-full text-center py-2.5 rounded-lg text-sm font-bold mb-5"
              style={{ background: "#1C1E24", color: "#F2F1EA", border: "1px solid #35D07F" }}
            >
              ✏️ Fill in my own availability
            </a>

            <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-5">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                Invite people
              </div>
              <div className="bg-[#14151A] border border-[#2C2F38] rounded-lg p-2.5 text-xs text-gray-300 break-all mb-2">
                {inviteLink || "Loading…"}
              </div>
              <button
                onClick={copyInviteLink}
                disabled={!inviteLink}
                className="w-full py-2 rounded-lg border text-sm font-bold mb-3"
                style={{ borderColor: "#2C2F38", background: "#14151A", color: "#C7C9D1" }}
              >
                {inviteCopied ? "Copied!" : "Copy invite link"}
              </button>

              <div className="flex gap-2 mb-2">
                <input
                  value={inviteEmail}
                  onChange={(e) => setInviteEmail(e.target.value)}
                  placeholder="Their email (optional)"
                  className="flex-1 box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-2.5 py-2 text-xs outline-none"
                />
                <button
                  onClick={inviteByEmail}
                  disabled={!inviteLink}
                  className="px-3 py-2 rounded-lg text-xs font-bold flex-shrink-0"
                  style={{ background: "#1C1E24", border: "1px solid #2C2F38", color: "#F2F1EA" }}
                >
                  Email invite
                </button>
              </div>
              <div className="flex gap-2">
                <input
                  value={invitePhone}
                  onChange={(e) => setInvitePhone(e.target.value)}
                  placeholder="Their phone (optional)"
                  className="flex-1 box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-2.5 py-2 text-xs outline-none"
                />
                <button
                  onClick={inviteByText}
                  disabled={!inviteLink}
                  className="px-3 py-2 rounded-lg text-xs font-bold flex-shrink-0"
                  style={{ background: "#1C1E24", border: "1px solid #2C2F38", color: "#F2F1EA" }}
                >
                  Text invite
                </button>
              </div>
              <p className="text-[11px] text-gray-500 mt-2">
                Email/text opens your own Mail or Messages app with the invite pre-filled --
                RLGL doesn't send anything itself. Leave the box blank to just get a blank
                message you can address yourself.
              </p>
            </div>

            <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-5">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                Repeat this session
              </div>
              <p className="text-[11px] text-gray-500 mb-3">
                Sets up a fresh poll for the same band with the same time blocks -- this
                session is untouched, and nobody's notified automatically. Good for a weekly
                thing (FBR) or a one-off you'll only reach for occasionally (Women In
                Harmony) -- it only runs when you click it.
              </p>
              <label className="text-[11px] text-gray-500 block mb-1">Title</label>
              <input
                value={repeatTitle}
                onChange={(e) => setRepeatTitle(e.target.value)}
                className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-2.5 py-2 text-sm mb-2.5 outline-none"
              />
              <label className="text-[11px] text-gray-500 block mb-1">New start date</label>
              <input
                type="date"
                value={repeatStartDate}
                onChange={(e) => setRepeatStartDate(e.target.value)}
                className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-2.5 py-2 text-sm mb-2.5 outline-none"
              />
              {repeatError && <p className="text-[#FF5A5F] text-xs mb-2">{repeatError}</p>}
              <button
                onClick={duplicateSession}
                disabled={repeating || !repeatStartDate}
                className="w-full py-2.5 rounded-lg text-sm font-bold"
                style={{ background: "#35D07F", color: "#0E1712" }}
              >
                {repeating ? "Creating…" : "Create the next one"}
              </button>
            </div>

            <Bulletin sessionId={params.id} authorName={ownerName} />
            <FileShare sessionId={params.id} canUpload />

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
                    downloadIcs(
                      `${confirmedTitle}.ics`,
                      confirmedTitle,
                      confirmedStartUtc,
                      confirmedEndUtc
                    )
                  }
                  className="w-full py-2 rounded-lg text-sm font-bold"
                  style={{ background: "#35D07F", color: "#0E1712" }}
                >
                  Download calendar invite (.ics)
                </button>
              </div>
            )}

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

            <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-7">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                Finalize a date
              </div>
              <select
                value={pickDate}
                onChange={(e) => setPickDate(e.target.value)}
                className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none mb-2"
              >
                {dates.map((d) => (
                  <option key={d} value={d}>
                    {formatFullDate(d)}
                  </option>
                ))}
              </select>
              <div className="flex gap-2 mb-2">
                <select
                  value={pickStartHour}
                  onChange={(e) => setPickStartHour(Number(e.target.value))}
                  className="flex-1 bg-[#14151A] border border-[#2C2F38] rounded-lg px-2 py-2 text-sm outline-none"
                >
                  {Array.from({ length: 24 }, (_, h) => (
                    <option key={h} value={h}>
                      {formatHour(h)}
                    </option>
                  ))}
                </select>
                <span className="text-gray-500 text-xs self-center">to</span>
                <select
                  value={pickEndHour}
                  onChange={(e) => setPickEndHour(Number(e.target.value))}
                  className="flex-1 bg-[#14151A] border border-[#2C2F38] rounded-lg px-2 py-2 text-sm outline-none"
                >
                  {Array.from({ length: 24 }, (_, h) => h + 1).map((h) => (
                    <option key={h} value={h}>
                      {formatHour(h)}
                    </option>
                  ))}
                </select>
              </div>
              <input
                value={pickTitle}
                onChange={(e) => setPickTitle(e.target.value)}
                placeholder="Event title"
                className="w-full box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none mb-3"
              />
              <button
                onClick={confirmSession}
                disabled={confirming || !pickDate || !pickTitle.trim()}
                className="w-full py-2.5 rounded-lg text-sm font-bold"
                style={{ background: "#35D07F", color: "#0E1712" }}
              >
                {confirming ? "Confirming…" : "Confirm this session"}
              </button>
            </div>

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">Calendar</div>
            <SummaryPaintCalendar startDate={startDate} endDate={endDate} dates={dates} blocks={blocks} counts={counts} total={total} />

            {members.length > 0 && (
              <div className="mt-8">
                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                  Individual responses
                </div>
                <p className="text-xs text-gray-500 mb-3">
                  Colors only — nobody's reasons are ever visible here, only to them.
                </p>
                {members.map((m) => {
                  const isOpen = expandedMember === m.id;
                  const hasResponded = !!memberStatuses[m.id] && Object.keys(memberStatuses[m.id]).length > 0;
                  return (
                    <div key={m.id} className="mb-2">
                      <button
                        onClick={() => setExpandedMember(isOpen ? null : m.id)}
                        className="w-full flex justify-between items-center px-3.5 py-2.5 rounded-lg border text-sm"
                        style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#F2F1EA" }}
                      >
                        <span className="font-bold">{m.name}</span>
                        <span className="text-xs text-gray-500">
                          {hasResponded ? (isOpen ? "Hide ▲" : "View ▼") : "No response yet"}
                        </span>
                      </button>
                      {isOpen && hasResponded && (
                        <div className="mt-2 pl-1">
                          <InteractivePaintCalendar
                            startDate={startDate}
                            endDate={endDate}
                            dates={dates}
                            blocks={blocks}
                            statuses={memberStatuses[m.id]}
                            onPaint={() => {}}
                            readOnly
                          />
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </>
        )}
      </div>
    </main>
  );
}
