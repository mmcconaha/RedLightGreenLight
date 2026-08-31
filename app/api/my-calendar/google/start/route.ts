import { NextResponse } from "next/server";
import { googleAuthUrl } from "@/lib/google";

// Reuses the SAME registered Google redirect URI as the per-session sync
// flow (app/api/auth/google/start) -- Google OAuth clients only allow a
// fixed set of redirect URIs, so rather than registering a second one in
// Google Cloud Console, the shared callback route branches on
// state.mode === "my-calendar" to tell the two flows apart.
export async function GET(req: Request) {
  const url = new URL(req.url);
  const userId = url.searchParams.get("userId");
  const tz = url.searchParams.get("tz") || "America/Chicago";

  if (!userId) {
    return NextResponse.json({ error: "Missing userId" }, { status: 400 });
  }

  const state = Buffer.from(JSON.stringify({ mode: "my-calendar", userId, tz })).toString("base64url");
  return NextResponse.redirect(googleAuthUrl(state));
}
