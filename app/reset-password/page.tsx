"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

export default function ResetPasswordPage() {
  const [ready, setReady] = useState(false);
  const [checking, setChecking] = useState(true);
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [msg, setMsg] = useState("");
  const [done, setDone] = useState(false);

  useEffect(() => {
    // Supabase parses the recovery link's tokens from the URL automatically
    // and fires this event once a recovery session is established.
    const { data: listener } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") {
        setReady(true);
        setChecking(false);
      }
    });

    // Fallback: if a session already exists by the time this page mounts
    // (event can fire before the listener is attached), check directly.
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) setReady(true);
      setChecking(false);
    });

    return () => listener.subscription.unsubscribe();
  }, []);

  const submit = async () => {
    setMsg("");
    if (password.length < 6) {
      setMsg("Password should be at least 6 characters.");
      return;
    }
    if (password !== confirmPassword) {
      setMsg("Passwords don't match.");
      return;
    }
    const { error } = await supabase.auth.updateUser({ password });
    if (error) {
      setMsg(error.message);
      return;
    }
    setDone(true);
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <div className="flex gap-2 mb-2">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-2xl font-black uppercase tracking-tight mb-6">Reset password</h1>

        {checking ? (
          <p className="text-sm text-gray-400">Checking your reset link…</p>
        ) : done ? (
          <div>
            <p className="text-sm text-gray-300 mb-4">Password updated. You're all set.</p>
            <a
              href="/dashboard"
              className="block w-full text-center py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              Go to dashboard
            </a>
          </div>
        ) : !ready ? (
          <div>
            <p className="text-sm text-gray-300 mb-4">
              This reset link is invalid or has expired. Request a new one from the login screen.
            </p>
            <a
              href="/dashboard"
              className="block w-full text-center py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#1C1E24", color: "#F2F1EA", border: "1px solid #2C2F38" }}
            >
              Back to login
            </a>
          </div>
        ) : (
          <div>
            <input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
              placeholder="New password"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            <input
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              type="password"
              placeholder="Confirm new password"
              className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2.5 text-[15px] mb-3 outline-none"
            />
            {msg && <p className="text-[#FF5A5F] text-xs mb-3">{msg}</p>}
            <button
              onClick={submit}
              className="w-full py-3 rounded-xl font-bold text-[15px]"
              style={{ background: "#35D07F", color: "#0E1712" }}
            >
              Set new password
            </button>
          </div>
        )}
      </div>
    </main>
  );
}
