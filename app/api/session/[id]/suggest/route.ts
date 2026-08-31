import { NextResponse } from "next/server";
import { supabase } from "@/lib/supabase";
import { topSuggestions, plainLine } from "@/lib/scoring";
import { CellCounts } from "@/lib/types";

// GET /api/session/[id]/suggest
// Reads only the aggregate counts (via the session_summary SQL function —
// see supabase/schema.sql) and ranks windows. The Claude call only writes
// the one-line "why", it never sees who responded or how.
export async function GET(_req: Request, { params }: { params: { id: string } }) {
  const { data, error } = await supabase.rpc("session_summary", {
    p_session_id: params.id,
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const cells = (data ?? []) as CellCounts[];
  const ranked = topSuggestions(cells);

  const withBlurbs = await Promise.all(
    ranked.map(async (s) => {
      const blurb = await writeBlurb(s.counts).catch(() => plainLine(s.counts));
      return { day_index: s.day_index, block_index: s.block_index, blurb };
    })
  );

  return NextResponse.json({ suggestions: withBlurbs, allCounts: cells });
}

async function writeBlurb(counts: CellCounts): Promise<string> {
  if (!process.env.ANTHROPIC_API_KEY) return plainLine(counts);

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": process.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-4-6",
      max_tokens: 60,
      messages: [
        {
          role: "user",
          content: `A band scheduling tool has a time slot with these counts: ${counts.green} free, ${counts.yellow} flexible, ${counts.red} busy, out of ${counts.responded} responses. Write one short, casual sentence (under 15 words) summarizing why this slot works. No names, no reasons for anyone's status, just the vibe of the numbers.`,
        },
      ],
    }),
  });

  const json = await res.json();
  const text = json?.content?.find((b: any) => b.type === "text")?.text;
  return text?.trim() || plainLine(counts);
}
