"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { formatFullDate } from "@/lib/dates";
import AppNav, { getHomeShortcut, setHomeShortcut, clearHomeShortcut, HomeShortcut } from "@/components/AppNav";

interface SessionRow {
  id: string;
  title: string;
  start_date: string;
  end_date: string;
}

interface BandGroup {
  id: string;
  name: string;
  sessions: SessionRow[];
}

export default function DashboardPage() {
  const [checking, setChecking] = useState(true);
  const [userId, setUserId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [magicLinkStatus, setMagicLinkStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [magicLinkError, setMagicLinkError] = useState("");
  const [showForgotPassword, setShowForgotPassword] = useState(false);
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotMsg, setForgotMsg] = useState("");

  const [ledBands, setLedBands] = useState<BandGroup[]>([]);
  const [memberBands, setMemberBands] = useState<BandGroup[]>([]);
  const [loadingData, setLoadingData] = useState(true);
  const [currentEmail, setCurrentEmail] = useState("");
  const [showPasswordChange, setShowPasswordChange] = useState(false);
  const [newPassword, setNewPassword] = useState("");
  const [passwordMsg, setPasswordMsg] = useState("");
  const [homeShortcut, setHomeShortcutState] = useState<HomeShortcut | null>(null);

  const loadDashboard = async (uid: string) => {
    setLoadingData(true);
    setHomeShortcutState(getHomeShortcut(uid));

    // Bands this person owns/leads
    const { data: owned } = await supabase.from("bands").select("id, name").eq("owner_id", uid);
    const ledGroups: BandGroup[] = [];
    for (const b of owned ?? []) {
      const { data: sessions } = await supabase
        .from("sessions")
        .select("id, title, start_date, end_date")
        .eq("band_id", b.id)
        .order("start_date", { ascending: false });
      ledGroups.push({ id: b.id, name: b.name, sessions: sessions ?? [] });
    }
    setLedBands(ledGroups);

    // Bands this person plays in (excluding ones they also own, to avoid duplicates)
    const { data: memberships } = await supabase
      .from("members")
      .select("band_id, name, bands(name)")
      .eq("user_id", uid);
    if (memberships && memberships.length > 0) {
      const selfName = (memberships[0] as any)?.name;
      if (selfName) setName(selfName);
    }
    const ownedIds = new Set((owned ?? []).map((b) => b.id));
    const memberGroups: BandGroup[] = [];
    for (const m of memberships ?? []) {
      const bandId = (m as any).band_id;
      if (ownedIds.has(bandId)) continue;
      const bandName = (m as any).bands?.name ?? "Unnamed band";
      const { data: sessions } = await supabase
        .from("sessions")
        .select("id, title, start_date, end_date")
        .eq("band_id", bandId)
        .order("start_date", { ascending: false });
      memberGroups.push({ id: bandId, name: bandName, sessions: sessions ?? [] });
    }
    setMemberBands(memberGroups);

    setLoadingData(false);
  };

  useEffect(() => {
    const init = async () => {
      const { data } = await supabase.auth.getSession();
      if (data.session) {
        setUserId(data.session.user.id);
        setCurrentEmail(data.session.user.email ?? "");
        await loadDashboard(data.session.user.id);
      }
      setChecking(false);
    };
    init();

    // Catches a magic link that finishes signing in just after this page has
    // already mounted (Supabase reads the token out of the URL asynchronously).
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_IN" && session?.user) {
        setUserId(session.user.id);
        setCurrentEmail(session.user.email ?? "");
        loadDashboard(session.user.id);
      }
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  const login = async () => {
    setLoginError("");
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      setLoginError("Couldn't log in — check your email/password.");
      return;
    }
    setUserId(data.user.id);
    setCurrentEmail(data.user.email ?? "");
    await loadDashboard(data.user.id);
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
      options: { emailRedirectTo: `${window.location.origin}/dashboard` },
    });
    if (error) {
      setMagicLinkStatus("error");
      setMagicLinkError(error.message);
    } else {
      setMagicLinkStatus("sent");
    }
  };

  const sendPasswordReset = async () => {
    setForgotMsg("");
    if (!forgotEmail) {
      setForgotMsg("Enter your email first.");
      return;
    }
    const { error } = await supabase.auth.resetPasswordForEmail(forgotEmail, {
      redirectTo: `${window.location.origin}/reset-password`,
    });
    if (error) {
      setForgotMsg(error.message);
    } else {
      setForgotMsg("Check your email for a reset link.");
    }
  };

  const pinAsHome = (bandId: string, bandName: string, sessionId: string, role: "organizer" | "respond") => {
    if (!userId) return;
    const shortcut: HomeShortcut = { href: `/session/${sessionId}/${role}`, label: bandName };
    setHomeShortcut(userId, shortcut);
    setHomeShortcutState(shortcut);
  };

  const unpinHome = () => {
    if (!userId) return;
    clearHomeShortcut(userId);
    setHomeShortcutState(null);
  };

  const logout = async () => {
    await supabase.auth.signOut();
    setUserId(null);
    setCurrentEmail("");
    setName("");
    setLedBands([]);
    setMemberBands([]);
  };

  const changePassword = async () => {
    setPasswordMsg("");
    if (newPassword.length < 6) {
      setPasswordMsg("Password should be at least 6 characters.");
      return;
    }
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    if (error) {
      setPasswordMsg(error.message);
    } else {
      setPasswordMsg("Password updated.");
      setNewPassword("");
    }
  };

  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] px-4 py-8">
      <div className="max-w-xl mx-auto">
        <div className="flex gap-2 mb-2">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-2xl font-black uppercase tracking-tight mb-6 break-all">
          {name ? `Welcome, ${name}` : currentEmail ? `Welcome, ${currentEmail}` : "Dashboard"}
        </h1>

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

            <button
              onClick={() => setShowForgotPassword(!showForgotPassword)}
              className="text-xs font-bold text-gray-400 mt-3"
            >
              {showForgotPassword ? "Cancel" : "Forgot password?"}
            </button>
            {showForgotPassword && (
              <div className="mt-2">
                <input
                  value={forgotEmail}
                  onChange={(e) => setForgotEmail(e.target.value)}
                  placeholder="Email"
                  className="w-full box-border bg-[#1C1E24] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm mb-2 outline-none"
                />
                <button
                  onClick={sendPasswordReset}
                  className="w-full py-2 rounded-lg text-sm font-bold"
                  style={{ background: "#1C1E24", color: "#F2F1EA", border: "1px solid #2C2F38" }}
                >
                  Send reset link
                </button>
                {forgotMsg && <p className="text-xs text-gray-400 mt-2">{forgotMsg}</p>}
              </div>
            )}
          </div>
        ) : loadingData ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : (
          <>
            <AppNav current="dashboard" />

            <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-7 mt-4">
              <div className="flex justify-between items-center mb-2">
                <div className="text-xs text-gray-400">
                  Logged in as <span className="text-gray-200 font-bold">{currentEmail}</span>
                </div>
                <button onClick={logout} className="text-xs font-bold text-[#FF5A5F]">
                  Log out
                </button>
              </div>
              <button
                onClick={() => setShowPasswordChange(!showPasswordChange)}
                className="text-xs font-bold text-gray-400"
              >
                {showPasswordChange ? "Cancel" : "Change password"}
              </button>
              {showPasswordChange && (
                <div className="mt-2 flex gap-2">
                  <input
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    type="password"
                    placeholder="New password"
                    className="flex-1 box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
                  />
                  <button
                    onClick={changePassword}
                    className="px-3 py-2 rounded-lg text-sm font-bold flex-shrink-0"
                    style={{ background: "#35D07F", color: "#0E1712" }}
                  >
                    Save
                  </button>
                </div>
              )}
              {passwordMsg && <p className="text-xs text-gray-400 mt-2">{passwordMsg}</p>}
            </div>

            <div className="mb-8">
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                Bands you lead
              </div>
              {ledBands.length === 0 ? (
                <p className="text-xs text-gray-500">None yet — create a session to start one.</p>
              ) : (
                ledBands.map((b) => {
                  const isHome = homeShortcut?.label === b.name && homeShortcut?.href.includes("/organizer");
                  const latestSessionId = b.sessions[0]?.id;
                  return (
                  <div key={b.id} className="mb-4">
                    <div className="flex justify-between items-center mb-1.5">
                      <div className="font-bold text-sm">{b.name}</div>
                      {latestSessionId && (
                        isHome ? (
                          <button onClick={unpinHome} className="text-[11px] font-bold text-[#35D07F] flex-shrink-0">
                            🏠 Home — unpin
                          </button>
                        ) : (
                          <button
                            onClick={() => pinAsHome(b.id, b.name, latestSessionId, "organizer")}
                            className="text-[11px] font-bold text-gray-400 flex-shrink-0"
                          >
                            📌 Set as home
                          </button>
                        )
                      )}
                    </div>
                    {b.sessions.length === 0 ? (
                      <p className="text-xs text-gray-500 pl-2">No sessions yet.</p>
                    ) : (
                      b.sessions.map((s) => (
                        <a
                          key={s.id}
                          href={`/session/${s.id}/organizer`}
                          className="block px-3 py-2.5 rounded-lg border text-sm mb-1.5"
                          style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#F2F1EA" }}
                        >
                          <div className="font-bold">{s.title}</div>
                          <div className="text-xs text-gray-500">
                            {formatFullDate(s.start_date)} – {formatFullDate(s.end_date)}
                          </div>
                        </a>
                      ))
                    )}
                  </div>
                  );
                })
              )}
            </div>

            <div>
              <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">
                Bands you play in
              </div>
              {memberBands.length === 0 ? (
                <p className="text-xs text-gray-500">
                  None yet — use an invite link from a band to join one.
                </p>
              ) : (
                memberBands.map((b) => {
                  const isHome = homeShortcut?.label === b.name && homeShortcut?.href.includes("/respond");
                  const latestSessionId = b.sessions[0]?.id;
                  return (
                  <div key={b.id} className="mb-4">
                    <div className="flex justify-between items-center mb-1.5">
                      <div className="font-bold text-sm">{b.name}</div>
                      {latestSessionId && (
                        isHome ? (
                          <button onClick={unpinHome} className="text-[11px] font-bold text-[#35D07F] flex-shrink-0">
                            🏠 Home — unpin
                          </button>
                        ) : (
                          <button
                            onClick={() => pinAsHome(b.id, b.name, latestSessionId, "respond")}
                            className="text-[11px] font-bold text-gray-400 flex-shrink-0"
                          >
                            📌 Set as home
                          </button>
                        )
                      )}
                    </div>
                    {b.sessions.length === 0 ? (
                      <p className="text-xs text-gray-500 pl-2">No sessions yet.</p>
                    ) : (
                      b.sessions.map((s) => (
                        <a
                          key={s.id}
                          href={`/session/${s.id}/respond`}
                          className="block px-3 py-2.5 rounded-lg border text-sm mb-1.5"
                          style={{ borderColor: "#2C2F38", background: "#1C1E24", color: "#F2F1EA" }}
                        >
                          <div className="font-bold">{s.title}</div>
                          <div className="text-xs text-gray-500">
                            {formatFullDate(s.start_date)} – {formatFullDate(s.end_date)}
                          </div>
                        </a>
                      ))
                    )}
                  </div>
                  );
                })
              )}
            </div>
          </>
        )}
      </div>
    </main>
  );
}
