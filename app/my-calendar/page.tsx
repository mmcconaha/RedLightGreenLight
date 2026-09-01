"use client";

// Unified "My Calendar" -- connect Google/Apple ONCE (per person, not per
// band membership) and see a big, bold, color-coded month view merging
// those calendars with every RLGL session you're part of, across every
// band. See lib/myCalendar.ts + app/api/my-calendar/* for the backend.
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { monthGrid } from "@/lib/dates";
import AppNav from "@/components/AppNav";

const GOOGLE_BLUE = "#4A9EFF";
const APPLE_GRAY = "#A8ADBA";
const RED = "#FF5A5F";
const YELLOW = "#FFC24B";
const GREEN = "#35D07F";
const BG = "#14151A";
const CARD = "#1C1E24";
const BORDER = "#2C2F38";
const TEXT = "#F2F1EA";

interface DayData {
  google: string[];
  apple: string[];
  rlgl: { status: "red" | "yellow" | "green" | "unresponded" | null; sessionTitles: string[] };
}

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

function dayBg(day: DayData | undefined): string {
  if (!day) return CARD;
  switch (day.rlgl.status) {
    case "red": return RED;
    case "yellow": return YELLOW;
    case "green": return GREEN;
    default: return CARD;
  }
}

function dayTextColor(day: DayData | undefined): string {
  if (!day) return TEXT;
  return day.rlgl.status === "yellow" || day.rlgl.status === "green" ? "#0E1712" : TEXT;
}

export default function MyCalendarPage() {
  const [checking, setChecking] = useState(true);
  const [userId, setUserId] = useState<string | null>(null);
  const [tz] = useState(() => {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone || "America/Chicago";
    } catch {
      return "America/Chicago";
    }
  });

  const [banner, setBanner] = useState<{ kind: "ok" | "error"; text: string } | null>(null);

  const [googleStatus, setGoogleStatus] = useState<{ connected: boolean; email: string | null; needsReconnect: boolean }>({
    connected: false,
    email: null,
    needsReconnect: false,
  });
  const [appleStatus, setAppleStatus] = useState<{ connected: boolean; email: string | null }>({
    connected: false,
    email: null,
  });
  const [appleEmail, setAppleEmail] = useState("");
  const [applePw, setApplePw] = useState("");
  const [appleConnecting, setAppleConnecting] = useState(false);
  const [appleMsg, setAppleMsg] = useState("");
  const [showAppleForm, setShowAppleForm] = useState(false);

  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth()); // 0-indexed

  const [monthData, setMonthData] = useState<Record<string, DayData>>({});
  const [loadingMonth, setLoadingMonth] = useState(false);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);

  const loadStatus = async (uid: string) => {
    const res = await fetch(`/api/my-calendar/status?userId=${uid}`);
    const json = await res.json();
    if (json.google) setGoogleStatus(json.google);
    if (json.apple) setAppleStatus(json.apple);
  };

  const loadMonth = async (uid: string, y: number, m: number) => {
    setLoadingMonth(true);
    const start = `${y}-${String(m + 1).padStart(2, "0")}-01`;
    const lastDay = new Date(y, m + 1, 0).getDate();
    const end = `${y}-${String(m + 1).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`;
    try {
      const res = await fetch(
        `/api/my-calendar/events?userId=${uid}&start=${start}&end=${end}&tz=${encodeURIComponent(tz)}`
      );
      const json = await res.json();
      if (json.ok) setMonthData(json.data);
    } catch {
      // leave the previous month's data up rather than blanking the grid
    }
    setLoadingMonth(false);
  };

  useEffect(() => {
    const init = async () => {
      const { data } = await supabase.auth.getSession();
      if (!data.session) {
        setChecking(false);
        return;
      }
      const uid = data.session.user.id;
      setUserId(uid);

      const params = new URLSearchParams(window.location.search);
      if (params.get("connected") === "google") {
        setBanner({ kind: "ok", text: "Google Calendar connected." });
      }
      const googleError = params.get("google_error");
      if (googleError) setBanner({ kind: "error", text: googleError });

      await loadStatus(uid);
      await loadMonth(uid, year, month);
      setChecking(false);
    };
    init();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (userId) loadMonth(userId, year, month);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [year, month]);

  const connectGoogle = () => {
    if (!userId) return;
    window.location.href = `/api/my-calendar/google/start?userId=${userId}&tz=${encodeURIComponent(tz)}`;
  };

  const connectApple = async () => {
    if (!userId) return;
    setAppleMsg("");
    if (!appleEmail || !applePw) {
      setAppleMsg("Enter both your Apple ID email and an app-specific password.");
      return;
    }
    setAppleConnecting(true);
    try {
      const res = await fetch("/api/my-calendar/apple/connect", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ userId, appleEmail, appSpecificPassword: applePw }),
      });
      const json = await res.json();
      if (!json.ok) {
        setAppleMsg(json.error || "Couldn't connect Apple Calendar.");
      } else {
        setAppleMsg("Connected.");
        setApplePw("");
        setShowAppleForm(false);
        await loadStatus(userId);
        await loadMonth(userId, year, month);
      }
    } catch (e: any) {
      setAppleMsg(e?.message || "Couldn't connect Apple Calendar.");
    }
    setAppleConnecting(false);
  };

  const disconnect = async (provider: "google" | "apple") => {
    if (!userId) return;
    await fetch("/api/my-calendar/disconnect", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ userId, provider }),
    });
    await loadStatus(userId);
    await loadMonth(userId, year, month);
  };

  const prevMonth = () => {
    if (month === 0) {
      setYear((y) => y - 1);
      setMonth(11);
    } else {
      setMonth((m) => m - 1);
    }
  };
  const nextMonth = () => {
    if (month === 11) {
      setYear((y) => y + 1);
      setMonth(0);
    } else {
      setMonth((m) => m + 1);
    }
  };
  const goToday = () => {
    setYear(now.getFullYear());
    setMonth(now.getMonth());
  };

  const grid = monthGrid(year, month);
  const todayISO = now.toISOString().slice(0, 10);
  const selectedDay = selectedDate ? monthData[selectedDate] : undefined;

  return (
    <main className="min-h-screen px-4 py-8" style={{ background: BG, color: TEXT }}>
      <div className="max-w-5xl mx-auto">
        <div className="flex gap-2 mb-2">
          <div className="w-2.5 h-2.5 rounded-full" style={{ background: RED }} />
          <div className="w-2.5 h-2.5 rounded-full" style={{ background: YELLOW }} />
          <div className="w-2.5 h-2.5 rounded-full" style={{ background: GREEN }} />
        </div>
        <h1 className="text-2xl font-black uppercase tracking-tight mb-1">My Calendar</h1>
        <p className="text-xs text-gray-400 mb-6">
          Connect once, see everything -- your real calendars plus every RLGL rehearsal, merged.
        </p>

        <AppNav current="my-calendar" />

        {checking ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : !userId ? (
          <div
            className="rounded-xl p-4 text-sm"
            style={{ background: CARD, border: `1px solid ${BORDER}` }}
          >
            You need to be logged in.{" "}
            <a href="/dashboard" className="font-bold underline">
              Log in on the dashboard
            </a>{" "}
            first, then come back here.
          </div>
        ) : (
          <>
            {banner && (
              <div
                className="rounded-lg px-3 py-2.5 text-sm font-bold mb-5"
                style={{
                  background: banner.kind === "ok" ? "rgba(53,208,127,0.15)" : "rgba(255,90,95,0.15)",
                  color: banner.kind === "ok" ? GREEN : RED,
                  border: `1px solid ${banner.kind === "ok" ? GREEN : RED}`,
                }}
              >
                {banner.text}
              </div>
            )}

            {/* Connection cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-6">
              <div className="rounded-xl p-4" style={{ background: CARD, border: `1px solid ${BORDER}` }}>
                <div className="flex items-center gap-2 mb-1">
                  <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: GOOGLE_BLUE }} />
                  <div className="font-bold text-sm">Google Calendar</div>
                </div>
                {googleStatus.connected ? (
                  <>
                    <p className="text-xs text-gray-400 mb-2">
                      Connected{googleStatus.email ? ` as ${googleStatus.email}` : ""}
                      {googleStatus.needsReconnect && (
                        <span style={{ color: YELLOW }}> -- needs reconnecting (weekly, Google's rule for apps still in testing)</span>
                      )}
                    </p>
                    <div className="flex gap-2">
                      <button
                        onClick={connectGoogle}
                        className="text-xs font-bold px-3 py-1.5 rounded-lg"
                        style={{ background: GOOGLE_BLUE, color: "#0E1712" }}
                      >
                        {googleStatus.needsReconnect ? "Reconnect" : "Refresh connection"}
                      </button>
                      <button onClick={() => disconnect("google")} className="text-xs font-bold" style={{ color: RED }}>
                        Disconnect
                      </button>
                    </div>
                  </>
                ) : (
                  <button
                    onClick={connectGoogle}
                    className="text-xs font-bold px-3 py-1.5 rounded-lg"
                    style={{ background: GOOGLE_BLUE, color: "#0E1712" }}
                  >
                    Connect Google Calendar
                  </button>
                )}
              </div>

              <div className="rounded-xl p-4" style={{ background: CARD, border: `1px solid ${BORDER}` }}>
                <div className="flex items-center gap-2 mb-1">
                  <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: APPLE_GRAY }} />
                  <div className="font-bold text-sm">Apple Calendar</div>
                </div>
                {appleStatus.connected ? (
                  <>
                    <p className="text-xs text-gray-400 mb-2">Connected as {appleStatus.email}</p>
                    <button onClick={() => disconnect("apple")} className="text-xs font-bold" style={{ color: RED }}>
                      Disconnect
                    </button>
                  </>
                ) : showAppleForm ? (
                  <div>
                    <input
                      value={appleEmail}
                      onChange={(e) => setAppleEmail(e.target.value)}
                      placeholder="Apple ID email"
                      className="w-full box-border bg-[#14151A] border rounded-lg px-2.5 py-2 text-xs mb-2 outline-none"
                      style={{ borderColor: BORDER }}
                    />
                    <input
                      value={applePw}
                      onChange={(e) => setApplePw(e.target.value)}
                      type="password"
                      placeholder="App-specific password"
                      className="w-full box-border bg-[#14151A] border rounded-lg px-2.5 py-2 text-xs mb-2 outline-none"
                      style={{ borderColor: BORDER }}
                    />
                    <p className="text-[11px] text-gray-500 mb-2">
                      Generate one at{" "}
                      <a href="https://appleid.apple.com" target="_blank" rel="noreferrer" className="underline">
                        appleid.apple.com
                      </a>{" "}
                      -- not your real Apple ID password.
                    </p>
                    <button
                      onClick={connectApple}
                      disabled={appleConnecting}
                      className="text-xs font-bold px-3 py-1.5 rounded-lg"
                      style={{ background: APPLE_GRAY, color: "#0E1712" }}
                    >
                      {appleConnecting ? "Connecting…" : "Connect"}
                    </button>
                    {appleMsg && <p className="text-[11px] mt-2" style={{ color: RED }}>{appleMsg}</p>}
                  </div>
                ) : (
                  <button
                    onClick={() => setShowAppleForm(true)}
                    className="text-xs font-bold px-3 py-1.5 rounded-lg"
                    style={{ background: APPLE_GRAY, color: "#0E1712" }}
                  >
                    Connect Apple Calendar
                  </button>
                )}
              </div>
            </div>

            {/* Legend */}
            <div className="flex flex-wrap gap-x-4 gap-y-1.5 text-[11px] text-gray-400 mb-4">
              <span><span className="inline-block w-2.5 h-2.5 rounded-full align-middle mr-1" style={{ background: RED }} />busy (RLGL)</span>
              <span><span className="inline-block w-2.5 h-2.5 rounded-full align-middle mr-1" style={{ background: YELLOW }} />maybe (RLGL)</span>
              <span><span className="inline-block w-2.5 h-2.5 rounded-full align-middle mr-1" style={{ background: GREEN }} />free (RLGL)</span>
              <span><span className="inline-block w-2.5 h-2.5 rounded-full align-middle mr-1 border" style={{ borderColor: YELLOW }} />needs your response</span>
              <span><span className="inline-block w-2.5 h-2.5 rounded-full align-middle mr-1" style={{ background: GOOGLE_BLUE }} />Google event</span>
              <span><span className="inline-block w-2.5 h-2.5 rounded-full align-middle mr-1" style={{ background: APPLE_GRAY }} />Apple event</span>
            </div>

            {/* Month nav */}
            <div className="flex items-center justify-between mb-3">
              <button onClick={prevMonth} className="text-lg font-black px-2" aria-label="Previous month">‹</button>
              <div className="font-bold text-lg">
                {MONTH_NAMES[month]} {year}
                {loadingMonth && <span className="text-xs text-gray-500 font-normal"> · loading…</span>}
              </div>
              <button onClick={nextMonth} className="text-lg font-black px-2" aria-label="Next month">›</button>
            </div>
            <button onClick={goToday} className="text-xs font-bold text-gray-400 mb-3 block">
              Jump to today
            </button>

            {/* Month grid -- big color blocks */}
            <div className="grid grid-cols-7 gap-2 mb-2">
              {["S", "M", "T", "W", "T", "F", "S"].map((d, i) => (
                <div key={i} className="text-center text-sm text-gray-500 font-bold">{d}</div>
              ))}
            </div>
            <div className="grid grid-cols-7 gap-2">
              {grid.flat().map((dateISO, i) => {
                if (!dateISO) return <div key={i} />;
                const day = monthData[dateISO];
                const isToday = dateISO === todayISO;
                const isSelected = dateISO === selectedDate;
                const items = [
                  ...((day?.google ?? []).map((title) => ({ title, color: GOOGLE_BLUE }))),
                  ...((day?.apple ?? []).map((title) => ({ title, color: APPLE_GRAY }))),
                ];
                const shownItems = items.slice(0, 3);
                const extraCount = items.length - shownItems.length;
                return (
                  <button
                    key={i}
                    onClick={() => setSelectedDate(isSelected ? null : dateISO)}
                    className="rounded-lg flex flex-col items-start p-1.5 text-left overflow-hidden"
                    style={{
                      background: dayBg(day),
                      color: dayTextColor(day),
                      minHeight: "128px",
                      border: isSelected
                        ? `2px solid ${TEXT}`
                        : isToday
                        ? `2px solid ${GOOGLE_BLUE}`
                        : day?.rlgl.status === "unresponded"
                        ? `2px dashed ${YELLOW}`
                        : `1px solid ${BORDER}`,
                    }}
                  >
                    <span className="text-lg font-black mb-1">{Number(dateISO.slice(8, 10))}</span>
                    <div className="flex flex-col gap-0.5 w-full">
                      {shownItems.map((item, idx) => (
                        <div
                          key={idx}
                          className="flex items-center gap-1.5 text-sm leading-tight rounded px-1.5 py-1 w-full"
                          style={{ background: "rgba(0,0,0,0.35)", color: "#F2F1EA" }}
                        >
                          <span
                            className="w-2 h-2 rounded-full flex-shrink-0"
                            style={{ background: item.color }}
                          />
                          <span className="truncate">{item.title}</span>
                        </div>
                      ))}
                      {extraCount > 0 && (
                        <div className="text-xs opacity-70 px-1.5">+{extraCount} more</div>
                      )}
                    </div>
                  </button>
                );
              })}
            </div>

            {/* Selected day detail */}
            {selectedDate && (
              <div className="mt-5 rounded-xl p-4" style={{ background: CARD, border: `1px solid ${BORDER}` }}>
                <div className="font-bold text-sm mb-2">
                  {new Date(selectedDate + "T00:00:00").toLocaleDateString("en-US", {
                    weekday: "long",
                    month: "long",
                    day: "numeric",
                  })}
                </div>
                {selectedDay?.rlgl.sessionTitles.length ? (
                  <p className="text-xs text-gray-400 mb-2">
                    RLGL: {selectedDay.rlgl.sessionTitles.join(", ")}
                    {selectedDay.rlgl.status === "unresponded" && (
                      <span style={{ color: YELLOW }}> -- you haven't responded yet</span>
                    )}
                  </p>
                ) : null}
                {selectedDay?.google.length ? (
                  <p className="text-xs mb-1">
                    <span style={{ color: GOOGLE_BLUE }} className="font-bold">Google:</span>{" "}
                    {selectedDay.google.join(", ")}
                  </p>
                ) : null}
                {selectedDay?.apple.length ? (
                  <p className="text-xs">
                    <span style={{ color: APPLE_GRAY }} className="font-bold">Apple:</span>{" "}
                    {selectedDay.apple.join(", ")}
                  </p>
                ) : null}
                {!selectedDay?.rlgl.sessionTitles.length && !selectedDay?.google.length && !selectedDay?.apple.length && (
                  <p className="text-xs text-gray-500">Nothing on this day.</p>
                )}
              </div>
            )}

            <a href="/dashboard" className="block text-xs font-bold text-gray-400 mt-8">
              ← Back to dashboard
            </a>
          </>
        )}
      </div>
    </main>
  );
}
