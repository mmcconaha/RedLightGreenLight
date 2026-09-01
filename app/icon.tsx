import { ImageResponse } from "next/og";

// Next.js auto-wires this into the favicon + <link rel="icon"> metadata --
// no manual <head> tags needed. Also reused as the PWA manifest icon (see
// app/manifest.ts) so there's exactly one source of truth for the app mark:
// a stoplight -- three stacked circles, red/yellow/green -- the same
// three-dot motif already used at the top of every page in the app.
export const size = { width: 192, height: 192 };
export const contentType = "image/png";

export default function Icon() {
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
          gap: 14,
          background: "#14151A",
          borderRadius: 36,
        }}
      >
        <div style={{ width: 40, height: 40, borderRadius: "50%", background: "#FF5A5F" }} />
        <div style={{ width: 40, height: 40, borderRadius: "50%", background: "#FFC24B" }} />
        <div style={{ width: 40, height: 40, borderRadius: "50%", background: "#35D07F" }} />
      </div>
    ),
    { ...size }
  );
}
