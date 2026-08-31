#!/bin/bash
set -e
mkdir -p "app/session/[id]/respond"
mkdir -p "app/join/[bandId]"
cat > "app/session/[id]/respond/page.tsx" << 'RESPOND_EOF'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { DEFAULT_DAYS, DEFAULT_BLOCKS, Status, STATUS_CYCLE } from "@/lib/types";
import { InteractiveGrid } from "@/components/Grid";

function emptyGrid(): Record<string, Status> {
  const g: Record<string, Status> = {};
  DEFAULT_DAYS.forEach((_, d) => DEFAULT_BLOCKS.forEach((_, b) => (g[`${d}-${b}`] = "unset")));
  return g;
}

export default function RespondPage({ params }: { params: { id: string } }) {
  const [checkingSession, setCheckingSession] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState("");

  const [grid, setGrid] = useState<Record<string, Status>>(emptyGrid());
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // On load, check if there's already a logged-in session and look up
  // their member row (RLS only lets them see their own row).
  useEffect(() => {
    const load = async () => {
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
        }
      }
      setCheckingSession(false);
    };
    load();
  }, []);

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
  };

  const cycleCell = (key: string) => {
    setGrid((prev) => {
      const cur = prev[key];
      const next = STATUS_CYCLE[(STATUS_CYCLE.indexOf(cur) + 1) % STATUS_CYCLE.length];
      return { ...prev, [key]: next };
    });
  };

  const submit = async () => {
    if (!memberId) return;
    setSubmitting(true);

    const rows = Object.entries(grid)
      .filter(([, status]) => status !== "unset")
      .map(([key, status]) => {
        const [day_index, block_index] = key.split("-").map(Number);
        return {
          session_id: params.id,
          member_id: memberId,
          day_index,
          block_index,
          status,
        };
      });

    // Upsert so re-submitting (changed your mind) overwrites, doesn't duplicate.
    await supabase
      .from("availability")
      .upsert(rows, { onConflict: "session_id,member_id,day_index,block_index" });

    setSubmitting(false);
    setSubmitted(true);
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
          One tap tells the band if you're free. No calendar, no explaining, no guilt.
        </p>

        <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3 text-sm text-gray-300 mb-6 flex gap-2">
          <span>🔒</span>
          <span>
            Nobody sees your reasons — only red, yellow, or green. Your answers stay private; the
            group only sees the combined light.
          </span>
        </div>

        {checkingSession ? (
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
        ) : submitted ? (
          <p className="text-[#35D07F] text-sm">
            Got it, {memberName} — thanks for not making this a whole thing.
          </p>
        ) : (
          <>
            <p className="text-sm text-gray-300 mb-3">Hey {memberName} — tap through your week:</p>
            <InteractiveGrid
              days={DEFAULT_DAYS}
              blocks={DEFAULT_BLOCKS}
              grid={grid}
              onCellClick={cycleCell}
            />
            <button
              onClick={submit}
              disabled={submitting}
              className="w-full mt-5 py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              {submitting ? "Sending…" : "Send my availability"}
            </button>
          </>
        )}
      </div>
    </main>
  );
}
RESPOND_EOF
cat > "app/join/[bandId]/page.tsx" << 'JOIN_EOF'
"use client";

import { useState } from "react";
import { useSearchParams } from "next/navigation";
import { supabase } from "@/lib/supabase";

export default function JoinPage({ params }: { params: { bandId: string } }) {
  const searchParams = useSearchParams();
  const sessionId = searchParams.get("session");

  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [joining, setJoining] = useState(false);
  const [joined, setJoined] = useState(false);

  const join = async () => {
    if (!name.trim() || !email.trim() || !password) return;
    setError("");
    setJoining(true);

    const { data, error: signUpError } = await supabase.auth.signUp({ email, password });
    if (signUpError || !data.user) {
      setError(signUpError?.message || "Couldn't create your account.");
      setJoining(false);
      return;
    }

    const { error: memberError } = await supabase
      .from("members")
      .insert({ band_id: params.bandId, name: name.trim(), user_id: data.user.id });

    if (memberError) {
      setError(memberError.message);
      setJoining(false);
      return;
    }

    setJoining(false);
    setJoined(true);

    if (sessionId) {
      window.location.href = `/session/${sessionId}/respond`;
    }
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8 flex items-center justify-center">
      <div className="max-w-sm w-full">
        <div className="flex gap-2 mb-3">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-2xl font-black uppercase leading-tight mb-2">
          You've been invited
        </h1>
        <p className="text-sm text-gray-400 mb-6">
          Join the RLGL platform to mark your availability — no back and forth, just tap red,
          yellow, or green.
        </p>

        {joined ? (
          <p className="text-[#35D07F] text-sm">You're in! Redirecting…</p>
        ) : (
          <>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Your name"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
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
              placeholder="Choose a password"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            {error && <p className="text-[#FF5A5F] text-xs mb-3">{error}</p>}
            <button
              onClick={join}
              disabled={joining || !name.trim() || !email.trim() || !password}
              className="w-full py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              {joining ? "Joining…" : "Join the band"}
            </button>
          </>
        )}
      </div>
    </main>
  );
}
JOIN_EOF
echo "Files created."
