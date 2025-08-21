export const metadata = { title: "ChillChill", description: "Operator" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark antialiased">
      <head><meta name="color-scheme" content="dark" /></head>
      <body className="min-h-screen bg-[var(--op-bg)] text-[var(--op-fg)]">{children}</body>
    </html>
  );
}