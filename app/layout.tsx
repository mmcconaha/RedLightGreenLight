import "./globals.css";

export const metadata = {
  title: "Red Light Green Light",
  description: "One tap tells the band if you're free.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
