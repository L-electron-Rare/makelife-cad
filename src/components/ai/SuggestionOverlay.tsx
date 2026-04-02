import { useState } from 'react'
import { X, Copy, Check, AlertCircle, AlertTriangle, Info } from 'lucide-react'
import { cn } from '../../lib/utils'

interface Issue {
  severity: 'error' | 'warning' | 'info'
  message: string
  suggestion: string
}

interface SuggestionOverlayProps {
  title: string
  issues: Issue[]
  onClose: () => void
}

const SEVERITY_CONFIG: Record<
  Issue['severity'],
  { icon: React.ReactNode; classes: string }
> = {
  error: {
    icon: <AlertCircle size={14} />,
    classes: 'text-red-400 bg-red-950/40 border-red-800/40',
  },
  warning: {
    icon: <AlertTriangle size={14} />,
    classes: 'text-yellow-400 bg-yellow-950/40 border-yellow-800/40',
  },
  info: {
    icon: <Info size={14} />,
    classes: 'text-blue-400 bg-blue-950/40 border-blue-800/40',
  },
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)

  const copy = async () => {
    await navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <button
      onClick={copy}
      className="flex items-center gap-1 text-xs text-zinc-500 hover:text-zinc-300 transition-colors"
    >
      {copied ? <Check size={11} /> : <Copy size={11} />}
      {copied ? 'Copied' : 'Copy'}
    </button>
  )
}

export function SuggestionOverlay({ title, issues, onClose }: SuggestionOverlayProps) {
  return (
    <div className="absolute right-0 top-0 bottom-0 w-96 bg-zinc-900 border-l border-zinc-800 flex flex-col shadow-2xl z-40">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800 shrink-0">
        <span className="text-sm font-medium text-zinc-200">{title}</span>
        <div className="flex items-center gap-2 text-xs text-zinc-500">
          <span>{issues.length} issue{issues.length !== 1 ? 's' : ''}</span>
          <button
            onClick={onClose}
            className="p-1 hover:text-zinc-300 hover:bg-zinc-800 rounded transition-colors"
          >
            <X size={14} />
          </button>
        </div>
      </div>

      {/* Issues list */}
      <div className="flex-1 overflow-y-auto p-3 space-y-2 min-h-0">
        {issues.length === 0 && (
          <p className="text-xs text-zinc-500 text-center pt-8">No issues found.</p>
        )}
        {issues.map((issue, i) => {
          const cfg = SEVERITY_CONFIG[issue.severity]
          return (
            <div
              key={i}
              className={cn('rounded-lg border px-3 py-2.5 space-y-1.5', cfg.classes)}
            >
              <div className="flex items-start gap-2">
                <span className="mt-0.5 shrink-0">{cfg.icon}</span>
                <p className="text-sm leading-relaxed flex-1">{issue.message}</p>
              </div>
              {issue.suggestion && (
                <div className="pl-5 space-y-1">
                  <p className="text-xs text-zinc-400 leading-relaxed">{issue.suggestion}</p>
                  <CopyButton text={issue.suggestion} />
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
