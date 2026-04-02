import { useEffect, useRef } from 'react'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import '@xterm/xterm/css/xterm.css'

interface TerminalPanelProps {
  sessionId: string | null
  isActive: boolean
}

export function TerminalPanel({ sessionId, isActive }: TerminalPanelProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const termRef = useRef<Terminal | null>(null)
  const fitAddonRef = useRef<FitAddon | null>(null)
  const attachedIdRef = useRef<string | null>(null)

  // Initialize xterm once
  useEffect(() => {
    if (!containerRef.current) return

    const term = new Terminal({
      theme: {
        background: '#09090b',
        foreground: '#e4e4e7',
        cursor: '#a1a1aa',
        selectionBackground: '#3f3f46',
      },
      fontFamily: '"JetBrains Mono", "Fira Code", monospace',
      fontSize: 13,
      lineHeight: 1.4,
      cursorBlink: true,
    })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.open(containerRef.current)
    fitAddon.fit()

    termRef.current = term
    fitAddonRef.current = fitAddon

    const resizeObs = new ResizeObserver(() => { fitAddon.fit() })
    resizeObs.observe(containerRef.current)

    return () => {
      resizeObs.disconnect()
      term.dispose()
    }
  }, [])

  // Attach / detach session
  useEffect(() => {
    const term = termRef.current
    if (!term || !window.terminal) return

    // Detach previous session listeners
    if (attachedIdRef.current && attachedIdRef.current !== sessionId) {
      window.terminal.removeDataListener(attachedIdRef.current)
    }

    if (!sessionId) return

    attachedIdRef.current = sessionId

    // Subscribe to PTY data
    window.terminal.onData(sessionId, (data) => term.write(data))
    window.terminal.onExit(sessionId, () => term.write('\r\n\x1b[90m[process exited]\x1b[0m\r\n'))

    // Forward keystrokes to PTY
    const disposeKey = term.onData((data) => {
      window.terminal.write(sessionId, data)
    })

    // Fit and notify PTY of dimensions
    const fitAddon = fitAddonRef.current
    if (fitAddon) {
      fitAddon.fit()
      window.terminal.resize(sessionId, term.cols, term.rows)
    }

    return () => {
      disposeKey.dispose()
    }
  }, [sessionId])

  // Re-fit when tab becomes active
  useEffect(() => {
    if (isActive && fitAddonRef.current && termRef.current && sessionId) {
      fitAddonRef.current.fit()
      window.terminal.resize(sessionId, termRef.current.cols, termRef.current.rows)
    }
  }, [isActive, sessionId])

  return (
    <div
      ref={containerRef}
      className="w-full h-full bg-zinc-950"
      style={{ display: isActive ? 'block' : 'none' }}
    />
  )
}
