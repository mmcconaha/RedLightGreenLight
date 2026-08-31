"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

interface Post {
  id: string;
  author_name: string;
  body: string;
  created_at: string;
}

export function Bulletin({ sessionId, authorName }: { sessionId: string; authorName: string }) {
  const [posts, setPosts] = useState<Post[]>([]);
  const [text, setText] = useState("");
  const [posting, setPosting] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    const { data } = await supabase
      .from("bulletin_posts")
      .select("id, author_name, body, created_at")
      .eq("session_id", sessionId)
      .order("created_at", { ascending: false });
    setPosts(data ?? []);
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, [sessionId]);

  const post = async () => {
    if (!text.trim()) return;
    setPosting(true);
    await supabase
      .from("bulletin_posts")
      .insert({ session_id: sessionId, author_name: authorName, body: text.trim() });
    setText("");
    setPosting(false);
    load();
  };

  return (
    <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-5">
      <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">Bulletin</div>
      <div className="flex gap-2 mb-3">
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Post an update for the band…"
          className="flex-1 box-border bg-[#14151A] border border-[#2C2F38] rounded-lg px-3 py-2 text-sm outline-none"
          onKeyDown={(e) => e.key === "Enter" && post()}
        />
        <button
          onClick={post}
          disabled={posting || !text.trim()}
          className="px-3 py-2 rounded-lg text-sm font-bold flex-shrink-0"
          style={{ background: "#35D07F", color: "#0E1712" }}
        >
          Post
        </button>
      </div>
      {loading ? (
        <p className="text-xs text-gray-500">Loading…</p>
      ) : posts.length === 0 ? (
        <p className="text-xs text-gray-500">No posts yet.</p>
      ) : (
        <div className="space-y-2 max-h-56 overflow-y-auto">
          {posts.map((p) => (
            <div key={p.id} className="text-sm">
              <span className="font-bold text-gray-200">{p.author_name}</span>
              <span className="text-gray-500 text-xs ml-1.5">
                {new Date(p.created_at).toLocaleString("en-US", {
                  month: "short",
                  day: "numeric",
                  hour: "numeric",
                  minute: "2-digit",
                })}
              </span>
              <div className="text-gray-300">{p.body}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
