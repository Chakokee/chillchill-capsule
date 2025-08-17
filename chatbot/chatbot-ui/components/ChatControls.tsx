"use client";
import { useState } from "react";

export type ChatControlsProps = {
  onSend?: (text: string) => void;
  placeholder?: string;
  disabled?: boolean;
};

export default function ChatControls({ onSend, placeholder = "Type a message…", disabled = false }: ChatControlsProps) {
  const [value, setValue] = useState("");
  return (
    <div className="flex gap-2 items-center">
      <input
        className="flex-1 p-2 rounded text-black"
        placeholder={placeholder}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        disabled={disabled}
      />
      <button
        className="px-3 py-2 rounded bg-gray-200 text-black disabled:opacity-50"
        onClick={() => { if (value.trim()) { onSend?.(value); setValue(""); } }}
        disabled={disabled}
      >
        Send
      </button>
    </div>
  );
}
