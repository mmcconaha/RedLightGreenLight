import { NextResponse } from "next/server";
import { connectApple } from "@/lib/myCalendar";

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const userId: string | undefined = body?.userId;
    const appleEmail: string | undefined = body?.appleEmail;
    const appSpecificPassword: string | undefined = body?.appSpecificPassword;

    if (!userId || !appleEmail || !appSpecificPassword) {
      return NextResponse.json(
        { ok: false, error: "userId, appleEmail, and appSpecificPassword are all required." },
        { status: 400 }
      );
    }

    try {
      await connectApple(userId, appleEmail, appSpecificPassword);
    } catch (e: any) {
      return NextResponse.json(
        {
          ok: false,
          error:
            e?.message ||
            "Couldn't connect with that email/app-specific password. Double-check both, and make sure the app-specific password hasn't been revoked.",
        },
        { status: 400 }
      );
    }

    return NextResponse.json({ ok: true, connected: true });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "unexpected error" }, { status: 500 });
  }
}
