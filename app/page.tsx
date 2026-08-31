export default function Home() {
  return (
    <main className="min-h-screen bg-[#14151A] text-[#F2F1EA] flex items-center justify-center px-4">
      <div className="text-center max-w-md">
        <div className="flex gap-2 justify-center mb-3">
          <div className="w-2.5 h-2.5 rounded-full bg-[#FF5A5F]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#FFC24B]" />
          <div className="w-2.5 h-2.5 rounded-full bg-[#35D07F]" />
        </div>
        <h1 className="text-3xl font-black uppercase mb-3">Red Light Green Light</h1>
        <p className="text-sm text-gray-400 mb-6">
          One tap tells the band if you're free. No calendar app, no explaining, no guilt.
        </p>
        <a
          href="/dashboard"
          className="inline-block px-6 py-2.5 rounded-lg text-sm font-bold"
          style={{ background: "#35D07F", color: "#0E1712" }}
        >
          Go to dashboard
        </a>
      </div>
    </main>
  );
}
