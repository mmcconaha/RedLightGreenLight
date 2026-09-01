import { ImageResponse } from "next/og";

// iOS specifically uses apple-touch-icon (not the web manifest icons) for
// the "Add to Home Screen" icon -- this is the one that actually matters
// for most of the 16 beta musicians, who are mostly on iPhones. Next.js
// auto-wires this file into the right <link rel="apple-touch-icon"> tag.
export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: 13,
          background: "#14151A",
        }}
      >
        <div style={{ width: 38, height: 38, borderRadius: "50%", background: "#FF5A5F" }} />
        <div style={{ width: 38, height: 38, borderRadius: "50%", background: "#FFC24B" }} />
        <div style={{ width: 38, height: 38, borderRadius: "50%", background: "#35D07F" }} />
      </div>
    ),
    { ...size }
  );
}
