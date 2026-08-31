import { NextResponse } from "next/server";
import { googleAuthUrl } from "@/lib/google";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const sessionId = url.searchParams.get("session");
  const memberId = url.searchParams.get("member");
  const tz = url.searchParams.get("tz") || "America/Chicago";

  if (!sessionId || !memberId) {
    return NextResponse.json({ error: "Missing session or member" }, { status: 400 });
  }

  const state = Buffer.from(JSON.stringify({ sessionId, memberId, tz })).toString("base64url");
  return NextResponse.redirect(googleAuthUrl(state));
}
