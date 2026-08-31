import { NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabaseAdmin";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const memberId = url.searchParams.get("memberId");
  if (!memberId) {
    return NextResponse.json({ connected: false }, { status: 400 });
  }
  const { data } = await supabaseAdmin
    .from("apple_credentials")
    .select("apple_email")
    .eq("member_id", memberId)
    .maybeSingle();
  return NextResponse.json({ connected: !!data, appleEmail: data?.apple_email ?? null });
}
