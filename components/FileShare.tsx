"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

interface FileItem {
  name: string;
  url: string;
}

export function FileShare({ sessionId, canUpload }: { sessionId: string; canUpload: boolean }) {
  const [files, setFiles] = useState<FileItem[]>([]);
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    const { data } = await supabase.storage.from("session-files").list(sessionId);
    const items = (data ?? [])
      .filter((f) => f.name !== ".emptyFolderPlaceholder")
      .map((f) => {
        const path = `${sessionId}/${f.name}`;
        const { data: pub } = supabase.storage.from("session-files").getPublicUrl(path);
        return { name: f.name, url: pub.publicUrl };
      });
    setFiles(items);
    setLoading(false);
  };

  useEffect(() => {
    load();
  }, [sessionId]);

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    await supabase.storage
      .from("session-files")
      .upload(`${sessionId}/${file.name}`, file, { upsert: true });
    setUploading(false);
    load();
  };

  return (
    <div className="bg-[#1C1E24] border border-[#2C2F38] rounded-xl p-3.5 mb-5">
      <div className="text-xs font-bold uppercase tracking-wide text-gray-400 mb-2">Files</div>
      {canUpload && (
        <label
          className="block w-full text-center py-2 rounded-lg border text-sm font-bold mb-3 cursor-pointer"
          style={{ borderColor: "#2C2F38", background: "#14151A", color: "#C7C9D1" }}
        >
          {uploading ? "Uploading…" : "+ Upload a file"}
          <input type="file" onChange={handleUpload} className="hidden" disabled={uploading} />
        </label>
      )}
      {loading ? (
        <p className="text-xs text-gray-500">Loading…</p>
      ) : files.length === 0 ? (
        <p className="text-xs text-gray-500">No files yet.</p>
      ) : (
        <div className="space-y-1.5">
          {files.map((f) => (
            <a
              key={f.name}
              href={f.url}
              target="_blank"
              rel="noreferrer"
              className="block text-sm text-[#35D07F] underline truncate"
            >
              {f.name}
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
