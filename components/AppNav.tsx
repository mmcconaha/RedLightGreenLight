"use client";

// Persistent, site-wide navigation bar. Renders on every main page
// (Dashboard, My Calendar, New session, Organizer, Respond) so nobody ever
// has to type or edit a URL to get around the app -- there are just buttons.
//
// Also owns the "home band" shortcut: a one-tap jump straight into whichever
// band/session someone cares about most, instead of going through the
// Dashboard's full list every time. It's pinnable (see setHomeShortcut,
// called from the Dashboard's "📌 Set as home" buttons) and falls back to
// auto-picking a sensible default (a led band over a played-in band, most
// recent session) when nothing's been pinned yet. Stored in localStorage --
// this is a personal, per-device shortcut, not shared band data, so there's
// no need for a migration.

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

export type PageKey = "dashboard" | "my-calendar" | "create" | "organizer" | "respond";

export interface HomeShortcut {
  href: string;
  label: string;
}

function homeKey(uid: string) {
  return `rlgl_home_${uid}`;
}

export function getHomeShortcut(uid: string): HomeShortcut | null {
  try {
    const raw = localStorage.getItem(homeKey(uid));
    return raw ? (JSON.parse(raw) as HomeShortcut) : null;
  } catch {
    return null;
  }
}

export function setHomeShortcut(uid: string, shortcut: HomeShortcut) {
  try {
    localStorage.setItem(homeKey(uid), JSON.stringify(shortcut));
  } catch {
    // localStorage unavailable -- the pin just won't stick, nothing to do.
  }
}

export function clearHomeShortcut(uid: string) {
  try {
    localStorage.removeItem(homeKey(uid));
  } catch {
    // ignore
  }
}

const BASE_BTN =
  "px-3 py-2 rounded-lg text-xs font-bold whitespace-nowrap flex-shrink-0";
const ACTIVE_STYLE = { background: "#35D07F", color: "#0E1712" };
const INACTIVE_STYLE = {
  background: "#1C1E24",
  color: "#F2F1EA",
  border: "1px solid #2C2F38",
};
const HOME_STYLE = {
  background: "#1C1E24",
  color: "#F2F1EA",
  border: "1px solid #35D07F",
};

async function autoDeriveHome(uid: string): Promise<HomeShortcut | null> {
  // Prefer a band they lead -- that's almost always the one someone opening
  // this app cares about jumping straight into.
  const { data: owned } = await supabase
    .from("bands")
    .select("id, name")
    .eq("owner_id", uid)
    .limit(1);
  if (owned && owned.length > 0) {
    const band = owned[0];
    const { data: sessions } = await supabase
      .from("sessions")
      .select("id")
      .eq("band_id", band.id)
      .order("start_date", { ascending: false })
      .limit(1);
    if (sessions && sessions.length > 0) {
      return { href: `/session/${sessions[0].id}/organizer`, label: band.name };
    }
  }

  // Otherwise, fall back to a band they just play in.
  const { data: memberships } = await supabase
    .from("members")
    .select("band_id, bands(name)")
    .eq("user_id", uid)
    .limit(1);
  if (memberships && memberships.length > 0) {
    const bandId = (memberships[0] as any).band_id;
    const bandName = (memberships[0] as any).bands?.name ?? "My band";
    const { data: sessions } = await supabase
      .from("sessions")
      .select("id")
      .eq("band_id", bandId)
      .order("start_date", { ascending: false })
      .limit(1);
    if (sessions && sessions.length > 0) {
      return { href: `/session/${sessions[0].id}/respond`, label: bandName };
    }
  }

  return null;
}

export default function AppNav({ current }: { current: PageKey }) {
  const [home, setHome] = useState<HomeShortcut | null>(null);

  useEffect(() => {
    let cancelled = false;
    const run = async () => {
      const { data } = await supabase.auth.getSession();
      const uid = data.session?.user?.id;
      if (!uid) return;

      const pinned = getHomeShortcut(uid);
      if (pinned) {
        if (!cancelled) setHome(pinned);
        return;
      }
      const derived = await autoDeriveHome(uid);
      if (!cancelled && derived) setHome(derived);
    };
    run();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="flex gap-2 mb-6 overflow-x-auto pb-1 -mx-4 px-4">
      <a href="/dashboard" className={BASE_BTN} style={current === "dashboard" ? ACTIVE_STYLE : INACTIVE_STYLE}>
        🏁 Dashboard
      </a>
      <a href="/my-calendar" className={BASE_BTN} style={current === "my-calendar" ? ACTIVE_STYLE : INACTIVE_STYLE}>
        🗓️ My Calendar
      </a>
      <a href="/create" className={BASE_BTN} style={current === "create" ? ACTIVE_STYLE : INACTIVE_STYLE}>
        + New session
      </a>
      {home && (
        <a href={home.href} className={BASE_BTN} style={HOME_STYLE} title={`Jump to ${home.label}`}>
          🏠 {home.label}
        </a>
      )}
    </div>
  );
}
