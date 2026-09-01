"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { BlockDef, SIMPLE_BLOCKS, WHOLE_DAY_BLOCKS } from "@/components/Calendar";
import AppNav from "@/components/AppNav";

type Mode = "simple" | "whole_day" | "custom";

const WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function formatHour(h: number): string {
  if (h === 24) return "12:00 AM (next day)";
  const period = h < 12 ? "AM" : "PM";
  let h12 = h % 12;
  if (h12 === 0) h12 = 12;
  return `${h12}:00 ${period}`;
}

export default function CreatePage() {
  const [checking, setChecking] = useState(true);
  const [userId, setUserId] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");

  const [bands, setBands] = useState<{ id: string; name: string }[]>([]);
  const [bandId, setBandId] = useState<string | null>(null);
  const [newBandName, setNewBandName] = useState("");
  const [creatingBand, setCreatingBand] = useState(false);

  const [title, setTitle] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [mode, setMode] = useState<Mode>("simple");
  const [activeWeekdays, setActiveWeekdays] = useState<number[]>([0, 1, 2, 3, 4, 5, 6]);
  const [customBlocks, setCustomBlocks] = useState<BlockDef[]>([
    { label: "", start_hour: 9, end_hour: 17 },
  ]);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState("");
  const [resultLink, setResultLink] = useState<string | null>(null);
  const [organizerLink, setOrganizerLink] = useState<string | null>(null);
  const [createdSessionId, setCreatedSessionId] = useState<string | null>(null);
  const [createdBandId, setCreatedBandId] = useState<string | null>(null);
  const [isMemberOfBand, setIsMemberOfBand] = useState(false);
  const [selfName, setSelfName] = useState("");
  const [addingSelf, setAddingSelf] = useState(false);

  useEffect(() => {
    const load = async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) {
        setUserId(data.session.user.id);
        await loadBands(data.session.user.id);
      }
      setChecking(false);
    };
    load();
  }, []);

  const loadBands = async (uid: string) => {
    const { data } = await supabase.from("bands").select("id, name").eq("owner_id", uid);
    setBands(data ?? []);
    if (data && data.length === 1) setBandId(data[0].id);
  };

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password.");
      return;
    }
    setUserId(data.user.id);
    await loadBands(data.user.id);
  };

  const createBand = async () => {
    if (!newBandName.trim() || !userId) return;
    setCreatingBand(true);
    const { data, error } = await supabase
      .from("bands")
      .insert({ name: newBandName.trim(), owner_id: userId })
      .select()
      .single();
    setCreatingBand(false);
    if (!error && data) {
      setBands((prev) => [...prev, data]);
      setBandId(data.id);
      setNewBandName("");
    }
  };

  const toggleWeekday = (d: number) => {
    setActiveWeekdays((prev) =>
      prev.includes(d) ? prev.filter((x) => x !== d) : [...prev, d].sort()
    );
  };

  const addCustomBlock = () => {
    setCustomBlocks((prev) => [...prev, { label: "", start_hour: 9, end_hour: 17 }]);
  };
  const updateCustomBlock = (i: number, patch: Partial<BlockDef>) => {
    setCustomBlocks((prev) => prev.map((b, idx) => (idx === i ? { ...b, ...patch } : b)));
  };
  const removeCustomBlock = (i: number) => {
    setCustomBlocks((prev) => prev.filter((_, idx) => idx !== i));
  };

  const createSession = async () => {
    if (!bandId || !title.trim() || !startDate || !endDate) return;
    setCreateError("");
    setCreating(true);

    let blocks: BlockDef[];
    if (mode === "simple") blocks = SIMPLE_BLOCKS;
    else if (mode === "whole_day") blocks = WHOLE_DAY_BLOCKS;
    else blocks = customBlocks.filter((b) => b.label.trim());

    if (mode === "custom" && blocks.length === 0) {
      setCreateError("Add at least one named block for custom mode.");
      setCreating(false);
      return;
    }

    const { data, error } = await supabase
      .from("sessions")
      .insert({
        band_id: bandId,
        title: title.trim(),
        start_date: startDate,
        end_date: endDate,
        mode,
        blocks,
        active_weekdays: activeWeekdays,
      })
      .select()
      .single();

    setCreating(false);
    if (error || !data) {
      setCreateError(error?.message || "Couldn't create session.");
      return;
    }

    const link = `${window.location.origin}/join/${bandId}?session=${data.id}`;
    const orgLink = `${window.location.origin}/session/${data.id}/organizer`;
    setResultLink(link);
    setOrganizerLink(orgLink);
    setCreatedSessionId(data.id);
    setCreatedBandId(bandId);

    const { data: existingMember } = await supabase
      .from("members")
      .select("id")
      .eq("band_id", bandId)
      .eq("user_id", userId)
      .single();
    setIsMemberOfBand(!!existingMember);
  };

  const copyLink = () => {
    if (resultLink) navigator.clipboard.writeText(resultLink);
  };
  const copyOrganizerLink = () => {
    if (organizerLink) navigator.clipboard.writeText(organizerLink);
  };

  const addSelfAsMember = async () => {
    if (!selfName.trim() || !userId || !createdBandId) return;
    setAddingSelf(true);
    const { error } = await supabase
      .from("members")
      .insert({ band_id: createdBandId, name: selfName.trim(), user_id: userId });
    setAddingSelf(false);
    if (!error) setIsMemberOfBand(true);
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <div className="flex gap-2 mb-2">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-2xl font-black uppercase tracking-tight mb-6">New Session</h1>

        <AppNav current="create" />

        {checking ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : !userId ? (
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
        ) : resultLink ? (
          <div>
            <p className="text-[#35D07F] text-sm mb-3">Session created.</p>

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
              Share this with the band
            </div>
            <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg p-3 text-xs text-gray-300 break-all mb-2">
              {resultLink}
            </div>
            <button
              onClick={copyLink}
              className="w-full py-2.5 rounded-lg border text-sm font-bold mb-5"
              style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#C7C9D1" }}
            >
              Copy invite link
            </button>

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
              Yours only — don't share this one
            </div>
            <div className="bg-[#1C1E24] border border-[#FFC24B] rounded-lg p-3 text-xs text-gray-300 break-all mb-2">
              {organizerLink}
            </div>
            <button
              onClick={copyOrganizerLink}
              className="w-full py-2.5 rounded-lg border text-sm font-bold mb-5"
              style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#C7C9D1" }}
            >
              Copy your organizer link
            </button>

            <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
              Are you also submitting availability?
            </div>
            {isMemberOfBand ? (
              <a
                href={`/session/${createdSessionId}/respond`}
                className="block w-full py-2.5 rounded-lg border text-sm font-bold text-center mb-5"
                style={{ borderColor: "#35D07F", background: "#1C2A22", color: "#35D07F" }}
              >
                You're set up — mark your own availability here
              </a>
            ) : (
              <div className="mb-5">
                <p className="text-xs text-gray-500 mb-2">
                  As the organizer you don't automatically get a member spot — add yourself if you're
                  also part of this session.
                </p>
                <div className="flex gap-2">
                  <input
                    value={selfName}
                    onChange={(e) => setSelfName(e.target.value)}
                    placeholder="Your name"
                    className="flex-1 box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                  />
                  <button
                    onClick={addSelfAsMember}
                    disabled={addingSelf || !selfName.trim()}
                    className="px-3 py-2 rounded-lg text-sm font-bold"
                    style={{ background: "#35D07F", color: "#0E1712" }}
                  >
                    {addingSelf ? "Adding…" : "Add myself"}
                  </button>
                </div>
              </div>
            )}

            <button
              onClick={() => {
                setResultLink(null);
                setOrganizerLink(null);
                setCreatedSessionId(null);
                setCreatedBandId(null);
                setIsMemberOfBand(false);
                setSelfName("");
                setTitle("");
                setStartDate("");
                setEndDate("");
              }}
              className="w-full py-2.5 rounded-lg text-sm font-bold"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              Create another session
            </button>
          </div>
        ) : (
          <>
            {/* Band picker */}
            <div className="mb-5">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">Band</div>
              {bands.length > 0 && (
                <div className="flex flex-wrap gap-2 mb-2">
                  {bands.map((b) => (
                    <button
                      key={b.id}
                      onClick={() => setBandId(b.id)}
                      className="px-3 py-1.5 rounded-lg border text-sm font-bold"
                      style={{
                        borderColor: bandId === b.id ? "#35D07F" : "#2C2F38",
                        background: bandId === b.id ? "#1C2A22" : "transparent",
                        color: bandId === b.id ? "#35D07F" : "#C7C9D1",
                      }}
                    >
                      {b.name}
                    </button>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <input
                  value={newBandName}
                  onChange={(e) => setNewBandName(e.target.value)}
                  placeholder="New band name"
                  className="flex-1 box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                />
                <button
                  onClick={createBand}
                  disabled={creatingBand || !newBandName.trim()}
                  className="px-3 py-2 rounded-lg text-sm font-bold"
                  style={{ background: "#35D07F", color: "#0E1712" }}
                >
                  + Add
                </button>
              </div>
            </div>

            {bandId && (
              <>
                <input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Session title (e.g. September rehearsals)"
                  className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
                />

                <div className="flex gap-2 mb-4">
                  <div className="flex-1">
                    <div className="text-xs text-gray-400 mb-1">Start date</div>
                    <input
                      type="date"
                      value={startDate}
                      onChange={(e) => setStartDate(e.target.value)}
                      className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                    />
                  </div>
                  <div className="flex-1">
                    <div className="text-xs text-gray-400 mb-1">End date</div>
                    <input
                      type="date"
                      value={endDate}
                      onChange={(e) => setEndDate(e.target.value)}
                      className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                    />
                  </div>
                </div>

                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                  Time frame
                </div>
                <div className="flex gap-2 mb-4">
                  {[
                    { value: "simple" as Mode, label: "Simple (AM/Mid/PM)" },
                    { value: "whole_day" as Mode, label: "Whole days only" },
                    { value: "custom" as Mode, label: "Custom" },
                  ].map((m) => (
                    <button
                      key={m.value}
                      onClick={() => setMode(m.value)}
                      className="flex-1 py-2 rounded-lg border text-xs font-bold"
                      style={{
                        borderColor: mode === m.value ? "#35D07F" : "#2C2F38",
                        background: mode === m.value ? "#1C2A22" : "transparent",
                        color: mode === m.value ? "#35D07F" : "#8B8E98",
                      }}
                    >
                      {m.label}
                    </button>
                  ))}
                </div>

                {mode === "custom" && (
                  <div className="mb-4">
                    <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                      Blocks
                    </div>
                    {customBlocks.map((b, i) => (
                      <div key={i} className="flex gap-2 mb-2 items-center">
                        <input
                          value={b.label}
                          onChange={(e) => updateCustomBlock(i, { label: e.target.value })}
                          placeholder="e.g. Load-in"
                          className="flex-1 box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-2 py-2 text-sm outline-none"
                        />
                        <select
                          value={b.start_hour}
                          onChange={(e) => updateCustomBlock(i, { start_hour: Number(e.target.value) })}
                          className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-1 py-2 text-xs outline-none"
                        >
                          {Array.from({ length: 24 }, (_, h) => (
                            <option key={h} value={h}>{formatHour(h)}</option>
                          ))}
                        </select>
                        <span className="text-gray-500 text-xs">to</span>
                        <select
                          value={b.end_hour}
                          onChange={(e) => updateCustomBlock(i, { end_hour: Number(e.target.value) })}
                          className="bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-1 py-2 text-xs outline-none"
                        >
                          {Array.from({ length: 24 }, (_, h) => h + 1).map((h) => (
                            <option key={h} value={h}>{formatHour(h)}</option>
                          ))}
                        </select>
                        <button
                          onClick={() => removeCustomBlock(i)}
                          className="text-[#FF5A5F] text-sm px-1"
                        >
                          ✕
                        </button>
                      </div>
                    ))}
                    <button
                      onClick={addCustomBlock}
                      className="text-xs font-bold text-[#35D07F]"
                    >
                      + Add block
                    </button>
                  </div>
                )}

                <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-1.5">
                  Days that count
                </div>
                <div className="flex gap-1.5 mb-5">
                  {WEEKDAY_LABELS.map((label, i) => (
                    <button
                      key={i}
                      onClick={() => toggleWeekday(i)}
                      className="flex-1 py-2 rounded-lg border text-xs font-bold"
                      style={{
                        borderColor: activeWeekdays.includes(i) ? "#35D07F" : "#2C2F38",
                        background: activeWeekdays.includes(i) ? "#1C2A22" : "transparent",
                        color: activeWeekdays.includes(i) ? "#35D07F" : "#8B8E98",
                      }}
                    >
                      {label}
                    </button>
                  ))}
                </div>

                {createError && <p className="text-[#FF5A5F] text-xs mb-3">{createError}</p>}

                <button
                  onClick={createSession}
                  disabled={creating || !title.trim() || !startDate || !endDate}
                  className="w-full py-3 rounded-xl font-bold text-[15px]"
                  style={{ background: "#35D07F", color: "#0E1712" }}
                >
                  {creating ? "Creating…" : "Create session"}
                </button>
              </>
            )}
          </>
        )}
      </div>
    </main>
  );
}
