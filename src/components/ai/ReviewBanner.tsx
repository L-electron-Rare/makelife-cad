import { useEffect, useRef } from 'react'
import { Search, X } from 'lucide-react'
import { cn } from '../../lib/utils'

interface ReviewBannerProps {
  type: 'schematic' | 'component'
  filePath: string
  onReview: (filePath: string) => void
  onDismiss: () => void
}

export function ReviewBanner({ type, filePath, onReview, onDismiss }: ReviewBannerProps) {
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    timerRef.current = setTimeout(onDismiss, 10_000)
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [onDismiss])

  const isSchematic = type === 'schematic'
  const fileName = filePath.split('/').pop() ?? filePath

  return (
    <div
      className={cn(
        'flex items-center gap-3 px-4 py-2 text-sm border-b',
        isSchematic
          ? 'bg-yellow-950/60 border-yellow-800/50 text-yellow-200'
          : 'bg-blue-950/60 border-blue-800/50 text-blue-200'
      )}
    >
      <Search size={14} className="shrink-0 opacity-70" />
      <span className="flex-1">
        {isSchematic
          ? `Review schematic \`${fileName}\` for errors and improvements?`
          : `Suggest components for \`${fileName}\`?`}
      </span>
      <button
        onClick={() => onReview(filePath)}
        className={cn(
          'px-2.5 py-1 rounded text-xs font-medium transition-colors',
          isSchematic
            ? 'bg-yellow-700 hover:bg-yellow-600 text-yellow-100'
            : 'bg-blue-700 hover:bg-blue-600 text-blue-100'
        )}
      >
        {isSchematic ? 'Review' : 'Suggest'}
      </button>
      <button
        onClick={onDismiss}
        className="text-zinc-500 hover:text-zinc-300 transition-colors"
      >
        <X size={14} />
      </button>
    </div>
  )
}
