"use client";

export type RagSource = { id?: string; title: string; snippet?: string; url?: string };
export type RagPanelProps = { sources?: RagSource[]; onOpen?: (src: RagSource) => void };

export default function RagPanel({ sources = [], onOpen }: RagPanelProps) {
  if (!sources.length) {
    return <div className="p-3 rounded bg-black/20">RAG: no sources</div>;
  }
  return (
    <div className="p-3 rounded bg-black/20 space-y-2">
      <div className="text-xs opacity-70">RAG Sources ({sources.length})</div>
      <ul className="space-y-1">
        {sources.map((s, i) => (
          <li key={s.id ?? String(i)} className="p-2 rounded bg-black/10 flex justify-between items-center">
            <span className="truncate">{s.title}</span>
            <button className="text-xs underline" onClick={() => onOpen?.(s)}>open</button>
          </li>
        ))}
      </ul>
    </div>
  );
}
