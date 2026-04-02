import { useState, useEffect, useCallback } from 'react'
import { ReviewBanner } from './ReviewBanner'
import { SuggestionOverlay } from './SuggestionOverlay'

interface Issue {
  severity: 'error' | 'warning' | 'info'
  message: string
  suggestion: string
}

interface InlineTriggersProps {
  currentFilePath?: string
  currentFileContent?: string
}

type BannerType = 'schematic' | 'component' | null

function isKicadSchematic(filePath: string) {
  return filePath.endsWith('.kicad_sch')
}

function hasHardwareDefines(content: string) {
  return /\b(GPIO|ADC|SPI|I2C|UART|PWM|PIN)\b/.test(content)
}

export function InlineTriggers({ currentFilePath, currentFileContent }: InlineTriggersProps) {
  const [bannerType, setBannerType] = useState<BannerType>(null)
  const [overlay, setOverlay] = useState<{ title: string; issues: Issue[] } | null>(null)
  const [loading, setLoading] = useState(false)

  // Decide which banner to show when the file changes
  useEffect(() => {
    if (!currentFilePath) {
      setBannerType(null)
      return
    }

    if (isKicadSchematic(currentFilePath)) {
      setBannerType('schematic')
      return
    }

    if (
      currentFileContent &&
      (currentFilePath.endsWith('.c') || currentFilePath.endsWith('.h')) &&
      hasHardwareDefines(currentFileContent)
    ) {
      setBannerType('component')
      return
    }

    setBannerType(null)
  }, [currentFilePath, currentFileContent])

  const handleReview = useCallback(async (filePath: string) => {
    if (!window.ai) return
    setBannerType(null)
    setLoading(true)

    try {
      const result = await window.ai.reviewSchematic(filePath)
      setOverlay({ title: 'Schematic Review', issues: result.issues as Issue[] })
    } catch (err) {
      setOverlay({
        title: 'Schematic Review',
        issues: [
          {
            severity: 'error',
            message: (err as Error).message,
            suggestion: '',
          },
        ],
      })
    } finally {
      setLoading(false)
    }
  }, [])

  const handleSuggest = useCallback(async (filePath: string) => {
    if (!window.ai || !currentFileContent) return
    setBannerType(null)
    setLoading(true)

    try {
      const result = await window.ai.suggestComponent(currentFileContent)
      const issues: Issue[] = result.components.map((c) => ({
        severity: 'info' as const,
        message: `${c.name} — ${c.value}`,
        suggestion: `Footprint: ${c.footprint}\n${c.reason}`,
      }))
      setOverlay({ title: 'Component Suggestions', issues })
    } catch (err) {
      setOverlay({
        title: 'Component Suggestions',
        issues: [
          {
            severity: 'error',
            message: (err as Error).message,
            suggestion: '',
          },
        ],
      })
    } finally {
      setLoading(false)
    }
  }, [currentFileContent])

  return (
    <>
      {/* Banner */}
      {bannerType && currentFilePath && (
        <ReviewBanner
          type={bannerType}
          filePath={currentFilePath}
          onReview={bannerType === 'schematic' ? handleReview : handleSuggest}
          onDismiss={() => setBannerType(null)}
        />
      )}

      {/* Loading indicator */}
      {loading && (
        <div className="px-4 py-2 text-xs text-zinc-500 border-b border-zinc-800 bg-zinc-900/50 animate-pulse">
          AI is analyzing...
        </div>
      )}

      {/* Results overlay */}
      {overlay && (
        <SuggestionOverlay
          title={overlay.title}
          issues={overlay.issues}
          onClose={() => setOverlay(null)}
        />
      )}
    </>
  )
}
