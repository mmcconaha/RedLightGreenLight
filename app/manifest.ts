import type { MetadataRoute } from "next";

// Lets a phone "Add to Home Screen" RLGL like a real app instead of just
// a bookmark -- reuses the same generated icon as the favicon (app/icon.tsx)
// so there's one app mark, not several to keep in sync.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Red Light Green Light",
    short_name: "RLGL",
    description: "One tap tells the band if you're free.",
    start_url: "/dashboard",
    display: "standalone",
    background_color: "#14151A",
    theme_color: "#14151A",
    icons: [
      { src: "/icon", sizes: "192x192", type: "image/png" },
      { src: "/apple-icon", sizes: "180x180", type: "image/png" },
    ],
  };
}
