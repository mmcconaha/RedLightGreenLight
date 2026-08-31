import { NextResponse } from "next/server";
import { runAppleSyncForSession } from "@/lib/appleSyncCore";

export async function POST(req: Request, { params }: { params: { id: string } }) {
  try {
    const body = await req.json();
    const memberId: string | undefined = body?.memberId;
    const tz: string = body?.tz || "America/Chicago";
    if (!memberId) {
      return NextResponse.json({ ok: false, error: "memberId is required" }, { status: 400 });
    }
    const result = await runAppleSyncForSession(params.id, memberId, tz);
    return NextResponse.json(result, { status: result.ok ? 200 : 400 });
  } catch (e: any) {
    return NextResponse.json({ ok: false, error: e?.message || "unexpected error" }, { status: 500 });
  }
}
