import "./globals.css";

export const metadata = {
  title: "Red Light Green Light",
  description: "One tap tells the band if you're free.",
};

// Colors the browser chrome (status bar / address bar) to match the app's
// dark background instead of leaving it default white -- part of making
// this feel like a real installed app rather than a random web page.
export const viewport = {
  themeColor: "#14151A",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
