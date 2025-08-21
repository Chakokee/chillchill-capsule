'use client';
import dynamic from 'next/dynamic';
const ChatControls = dynamic(() => import('./ChatControls'), { ssr: false });
export default function ChatControlsClient(){ return <ChatControls />; }
