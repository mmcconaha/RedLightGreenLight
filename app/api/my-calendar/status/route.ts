import { NextResponse } from "next/server";
import { getConnectionStatus } from "@/lib/myCalendar";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const userId = url.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json({ error: "Missing userId" }, { status: 400 });
  }
  const status = await getConnectionStatus(userId);
  return NextResponse.json(status);
}
