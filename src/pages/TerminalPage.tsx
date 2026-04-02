import { TerminalTabs } from '../components/terminal/TerminalTabs'

export default function TerminalPage() {
  if (typeof window !== 'undefined' && !window.terminal) {
    return (
      <div className="flex items-center justify-center h-full text-zinc-500 text-sm">
        Terminal requires the desktop app (Electron).
      </div>
    )
  }

  return (
    <div className="h-full w-full">
      <TerminalTabs />
    </div>
  )
}
