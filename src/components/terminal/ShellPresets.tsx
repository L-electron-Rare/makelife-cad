import { Terminal, Cpu, Waves, Hammer } from 'lucide-react'

export type ShellPreset = 'shell' | 'platformio' | 'ngspice' | 'cmake'

interface Preset {
  id: ShellPreset
  label: string
  icon: React.ReactNode
  description: string
}

const PRESETS: Preset[] = [
  {
    id: 'shell',
    label: 'Shell',
    icon: <Terminal size={14} />,
    description: 'Default shell (zsh/bash)',
  },
  {
    id: 'platformio',
    label: 'PlatformIO',
    icon: <Cpu size={14} />,
    description: 'PlatformIO CLI environment',
  },
  {
    id: 'ngspice',
    label: 'ngspice',
    icon: <Waves size={14} />,
    description: 'ngspice interactive simulator',
  },
  {
    id: 'cmake',
    label: 'CMake',
    icon: <Hammer size={14} />,
    description: 'CMake build environment',
  },
]

interface ShellPresetsProps {
  onSelect: (preset: ShellPreset) => void
  onClose: () => void
}

export function ShellPresets({ onSelect, onClose }: ShellPresetsProps) {
  return (
    <div className="absolute z-50 bottom-8 left-4 bg-zinc-900 border border-zinc-700 rounded-lg shadow-xl min-w-52 overflow-hidden">
      <div className="px-3 py-2 border-b border-zinc-700 text-xs text-zinc-400 font-medium uppercase tracking-wide">
        New Terminal
      </div>
      {PRESETS.map((preset) => (
        <button
          key={preset.id}
          onClick={() => { onSelect(preset.id); onClose() }}
          className="w-full flex items-center gap-3 px-3 py-2.5 text-sm text-zinc-200 hover:bg-zinc-800 transition-colors text-left"
        >
          <span className="text-zinc-400">{preset.icon}</span>
          <div>
            <div className="font-medium">{preset.label}</div>
            <div className="text-xs text-zinc-500">{preset.description}</div>
          </div>
        </button>
      ))}
    </div>
  )
}
