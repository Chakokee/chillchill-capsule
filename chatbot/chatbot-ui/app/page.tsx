import ChatControlsClient from "../components/ChatControlsClient";

export default function HomePage() {
  return (
    <main className="p-6">
      <div className="max-w-3xl mx-auto space-y-4">
        <h1 className="text-xl font-semibold">ChillChill</h1>
        <ChatControlsClient />
      </div>
    </main>
  );
}
