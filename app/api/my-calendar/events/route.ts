import { NextResponse } from "next/server";
import { fetchMonthData } from "@/lib/myCalendar";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const userId = url.searchParams.get("userId");
  const start = url.searchParams.get("start");
  const end = url.searchParams.get("end");
  const tz = url.searchParams.get("tz") || "America/Chicago";

  if (!userId || !start || !end) {
    return NextResponse.json({ error: "userId, start, and end are all required." }, { status: 400 });
  }

  try {
    const data = await fetchMonthData(userId, start, end, tz);
    return NextResponse.json({ ok: true, data });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "unexpected error" }, { status: 500 });
  }
}
