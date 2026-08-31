#!/bin/bash
set -e
echo "Writing lib/ics.ts..."
cat > "lib/ics.ts" << 'ICS_EOF'
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
ICS_EOF
echo "Writing components/Bulletin.tsx..."
cat > "components/Bulletin.tsx" << 'BULLETIN_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

interface Post {
  id: string;
  author_name: string;
  body: string;
  created_at: string;
}

export function Bulletin({ sessionId, authorName }: { sessionId: string; authorName: string }) {
  const [posts, setPosts] = useState<Post[]>([]);
  const [text, setText] = useState("");
  const [posting, setPosting] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    const { data } = await supabase
      .from("bulletin_posts")
      .select("id, author_name, body, created_at")
      .eq("session_id", sessionId)
      .order("created_at", { ascending: false });
    setPosts(data ?? []);
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, [sessionId]);

  const post = async () => {
    if (!text.trim()) return;
    setPosting(true);
    await supabase
      .from("bulletin_posts")
      .insert({ session_id: sessionId, author_name: authorName, body: text.trim() });
    setText("");
    setPosting(false);
    load();
  };

  return (
    <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-5">
      <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">Bulletin</div>
      <div className="flex gap-2 mb-3">
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Post an update for the band…"
          className="flex-1 box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
          onKeyDown={(e) => e.key === "Enter" && post()}
        />
        <button
          onClick={post}
          disabled={posting || !text.trim()}
          className="px-3 py-2 rounded-lg text-sm font-bold flex-shrink-0"
          style={{ background: "#35D07F", color: "#0E1712" }}
        >
          Post
        </button>
      </div>
      {loading ? (
        <p className="text-xs text-gray-500">Loading…</p>
      ) : posts.length === 0 ? (
        <p className="text-xs text-gray-500">No posts yet.</p>
      ) : (
        <div className="space-y-2 max-h-56 overflow-y-auto">
          {posts.map((p) => (
            <div key={p.id} className="text-sm">
              <span className="font-bold text-gray-200">{p.author_name}</span>
              <span className="text-gray-500 text-xs ml-1.5">
                {new Date(p.created_at).toLocaleString("en-US", {
                  month: "short",
                  day: "numeric",
                  hour: "numeric",
                  minute: "2-digit",
                })}
              </span>
              <div className="text-gray-300">{p.body}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
BULLETIN_EOF
echo "Writing components/FileShare.tsx..."
cat > "components/FileShare.tsx" << 'FILESHARE_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

interface FileItem {
  name: string;
  url: string;
}

export function FileShare({ sessionId, canUpload }: { sessionId: string; canUpload: boolean }) {
  const [files, setFiles] = useState<FileItem[]>([]);
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    const { data } = await supabase.storage.from("session-files").list(sessionId);
    const items = (data ?? [])
      .filter((f) => f.name !== ".emptyFolderPlaceholder")
      .map((f) => {
        const path = `${sessionId}/${f.name}`;
        const { data: pub } = supabase.storage.from("session-files").getPublicUrl(path);
        return { name: f.name, url: pub.publicUrl };
      });
    setFiles(items);
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, [sessionId]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    await supabase.storage
      .from("session-files")
      .upload(`${sessionId}/${file.name}`, file, { upsert: true });
    setUploading(false);
    load();
  };

  return (
    <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-5">
      <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">Files</div>
      {canUpload && (
        <label
          className="block w-full text-center py-2 rounded-lg border text-sm font-bold mb-3 cursor-pointer"
          style={{ borderColor: "#2C2F38", background: "#14151A", color: "#C7C9D1" }}
        >
          {uploading ? "Uploading…" : "+ Upload a file"}
          <input type="file" onChange={handleUpload} className="hidden" disabled={uploading} />
        </label>
      )}
      {loading ? (
        <p className="text-xs text-gray-500">Loading…</p>
      ) : files.length === 0 ? (
        <p className="text-xs text-gray-500">No files yet.</p>
      ) : (
        <div className="space-y-1.5">
          {files.map((f) => (
            <a
              key={f.name}
              href={f.url}
              target="_blank"
              rel="noreferrer"
              className="block text-sm text-[#35D07F] underline truncate"
            >
              {f.name}
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
FILESHARE_EOF
echo "Writing organizer page..."
cat > "app/session/[id]/organizer/page.tsx" << 'ORG_EOF'
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
  const [ownerName, setOwnerName] = useState("Organizer");

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
    const d = dateRangeFiltered(session.start_date, session.end_date, activeWeekdays);
    setDates(d);
    if (d.length > 0) setPickDate(d[0]);

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
          await loadSessionData(session.band_id, authData.session.user.id);
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
    await loadSessionData(session.band_id, data.user.id);
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
ORG_EOF
echo "Writing respond page..."
cat > "app/session/[id]/respond/page.tsx" << 'RESPOND_EOF'
"use client";

import { useEffect, useState, useRef } from "react";
import { supabase } from "@/lib/supabase";
import { Status } from "@/lib/types";
import { dateRangeFiltered } from "@/lib/dates";
import { InteractivePaintCalendar, BlockDef, SIMPLE_BLOCKS, cellKey } from "@/components/Calendar";
import { Bulletin } from "@/components/Bulletin";
import { FileShare } from "@/components/FileShare";
import { downloadIcs } from "@/lib/ics";

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
  const [confirmedTitle, setConfirmedTitle] = useState<string | null>(null);
  const [confirmedStartUtc, setConfirmedStartUtc] = useState<string | null>(null);
  const [confirmedEndUtc, setConfirmedEndUtc] = useState<string | null>(null);

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
        .select("start_date, end_date, blocks, active_weekdays, confirmed_title, confirmed_start_utc, confirmed_end_utc")
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
echo "All files updated."
