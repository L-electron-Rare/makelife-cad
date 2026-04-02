import { useState, useCallback } from 'react'
import { Plus, X, Terminal, Cpu, Waves, Hammer } from 'lucide-react'
import { cn } from '../../lib/utils'
import { TerminalPanel } from './TerminalPanel'
import { ShellPresets, ShellPreset } from './ShellPresets'

interface TabInfo {
  id: string
  sessionId: string | null
  preset: ShellPreset
  label: string
  hasUnread: boolean
}

const PRESET_ICONS: Record<ShellPreset, React.ReactNode> = {
  shell: <Terminal size={12} />,
  platformio: <Cpu size={12} />,
  ngspice: <Waves size={12} />,
  cmake: <Hammer size={12} />,
}

const PRESET_LABELS: Record<ShellPreset, string> = {
  shell: 'Shell',
  platformio: 'PlatformIO',
  ngspice: 'ngspice',
  cmake: 'CMake',
}

let tabCounter = 0

export function TerminalTabs() {
  const [tabs, setTabs] = useState<TabInfo[]>([])
  const [activeTabId, setActiveTabId] = useState<string | null>(null)
  const [showPresets, setShowPresets] = useState(false)

  const openTab = useCallback(async (preset: ShellPreset) => {
    if (!window.terminal) return
    const sessionId = await window.terminal.spawn(preset, undefined)
    const id = `tab-${++tabCounter}`
    const tab: TabInfo = {
      id,
      sessionId,
      preset,
      label: `${PRESET_LABELS[preset]} ${tabCounter}`,
      hasUnread: false,
    }
    setTabs((prev) => [...prev, tab])
    setActiveTabId(id)
  }, [])

  const closeTab = useCallback(async (tabId: string) => {
    const tab = tabs.find((t) => t.id === tabId)
    if (tab?.sessionId) await window.terminal.kill(tab.sessionId)

    setTabs((prev) => {
      const next = prev.filter((t) => t.id !== tabId)
      if (activeTabId === tabId) {
        setActiveTabId(next.length > 0 ? next[next.length - 1].id : null)
      }
      return next
    })
  }, [tabs, activeTabId])

  return (
    <div className="flex flex-col h-full bg-zinc-950">
      {/* Tab bar */}
      <div className="flex items-center bg-zinc-900 border-b border-zinc-800 min-h-9 overflow-x-auto shrink-0">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTabId(tab.id)}
            className={cn(
              'flex items-center gap-1.5 px-3 py-1.5 text-xs border-r border-zinc-800 whitespace-nowrap',
              'hover:bg-zinc-800 transition-colors group',
              activeTabId === tab.id
                ? 'bg-zinc-950 text-zinc-100'
                : 'text-zinc-400'
            )}
          >
            <span className={tab.hasUnread ? 'text-yellow-400' : 'text-zinc-500'}>
              {PRESET_ICONS[tab.preset]}
            </span>
            {tab.label}
            {tab.hasUnread && (
              <span className="w-1.5 h-1.5 rounded-full bg-yellow-400 ml-0.5" />
            )}
            <span
              onClick={(e) => { e.stopPropagation(); closeTab(tab.id) }}
              className="ml-1 opacity-0 group-hover:opacity-100 hover:text-zinc-100 transition-opacity"
            >
              <X size={10} />
            </span>
          </button>
        ))}

        {/* New tab button */}
        <div className="relative ml-1">
          <button
            onClick={() => setShowPresets((v) => !v)}
            className="flex items-center justify-center w-7 h-7 text-zinc-500 hover:text-zinc-200 hover:bg-zinc-800 rounded transition-colors"
          >
            <Plus size={14} />
          </button>
          {showPresets && (
            <ShellPresets
              onSelect={openTab}
              onClose={() => setShowPresets(false)}
            />
          )}
        </div>
      </div>

      {/* Terminal panels */}
      <div className="flex-1 min-h-0 relative">
        {tabs.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-zinc-600 gap-3">
            <Terminal size={32} />
            <p className="text-sm">No terminal open</p>
            <button
              onClick={() => setShowPresets(true)}
              className="text-xs text-zinc-500 hover:text-zinc-300 underline underline-offset-2 transition-colors"
            >
              Open a new terminal
            </button>
          </div>
        ) : (
          tabs.map((tab) => (
            <div key={tab.id} className="absolute inset-0">
              <TerminalPanel
                sessionId={tab.sessionId}
                isActive={tab.id === activeTabId}
              />
            </div>
          ))
        )}
      </div>
    </div>
  )
}
