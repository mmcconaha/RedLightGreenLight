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
