import { NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabaseAdmin";
import { verifyAppleCredentials } from "@/lib/apple";
import { encryptSecret } from "@/lib/appleCrypto";
import { runAppleSyncForSession } from "@/lib/appleSyncCore";

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const memberId: string | undefined = body?.memberId;
    const appleEmail: string | undefined = body?.appleEmail;
    const appSpecificPassword: string | undefined = body?.appSpecificPassword;
    const sessionId: string | undefined = body?.sessionId;
    const tz: string = body?.tz || "America/Chicago";

    if (!memberId || !appleEmail || !appSpecificPassword) {
      return NextResponse.json(
        { ok: false, error: "memberId, appleEmail, and appSpecificPassword are all required." },
        { status: 400 }
      );
    }

    try {
      await verifyAppleCredentials(appleEmail, appSpecificPassword);
    } catch {
      return NextResponse.json(
        {
          ok: false,
          error:
            "Couldn't connect with that email/app-specific password. Double-check both, and make sure the app-specific password hasn't been revoked.",
        },
        { status: 400 }
      );
    }

    const encrypted = encryptSecret(appSpecificPassword);
    const { error: upsertError } = await supabaseAdmin.from("apple_credentials").upsert(
      {
        member_id: memberId,
        apple_email: appleEmail,
        encrypted_password: encrypted,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "member_id" }
    );
    if (upsertError) {
      return NextResponse.json({ ok: false, error: upsertError.message }, { status: 500 });
    }

    if (sessionId) {
      const sync = await runAppleSyncForSession(sessionId, memberId, tz);
      return NextResponse.json({ ok: true, connected: true, sync });
    }

    return NextResponse.json({ ok: true, connected: true });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "unexpected error" }, { status: 500 });
  }
}
