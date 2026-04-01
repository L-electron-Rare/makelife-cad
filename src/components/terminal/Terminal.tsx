import { useEffect, useRef } from 'react'
import { Terminal as XTerm } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import '@xterm/xterm/css/xterm.css'

interface TerminalProps { output?: string }

export function Terminal({ output }: TerminalProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const termRef = useRef<XTerm | null>(null)

  useEffect(() => {
    if (!containerRef.current) return
    const term = new XTerm({
      theme: { background: '#0f172a', foreground: '#e2e8f0', cursor: '#60a5fa' },
      fontSize: 13,
      fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
      cursorBlink: true,
    })
    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.open(containerRef.current)
    fitAddon.fit()
    termRef.current = term
    const ro = new ResizeObserver(() => fitAddon.fit())
    ro.observe(containerRef.current)
    return () => { ro.disconnect(); term.dispose() }
  }, [])

  useEffect(() => {
    if (output && termRef.current) termRef.current.write(output.replace(/\n/g, '\r\n'))
  }, [output])

  return <div ref={containerRef} className="h-full w-full" />
}
