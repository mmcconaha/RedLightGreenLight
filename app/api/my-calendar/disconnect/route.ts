import { NextResponse } from "next/server";
import { disconnectProvider } from "@/lib/myCalendar";

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const userId: string | undefined = body?.userId;
    const provider: "google" | "apple" | undefined = body?.provider;
    if (!userId || (provider !== "google" && provider !== "apple")) {
      return NextResponse.json({ ok: false, error: "userId and a valid provider are required." }, { status: 400 });
    }
    await disconnectProvider(userId, provider);
    return NextResponse.json({ ok: true });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "unexpected error" }, { status: 500 });
  }
}
