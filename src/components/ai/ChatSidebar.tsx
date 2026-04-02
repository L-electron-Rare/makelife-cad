import { useState, useRef, useEffect, useCallback } from 'react'
import { Send, Paperclip, Trash2, ChevronRight } from 'lucide-react'
import { cn } from '../../lib/utils'

interface Message {
  role: 'user' | 'assistant'
  content: string
}

const MODELS = [
  { id: 'openai/qwen-14b-awq', label: 'Qwen 14B AWQ' },
  { id: 'anthropic/claude-3-5-sonnet', label: 'Claude 3.5 Sonnet' },
  { id: 'openai/gpt-4o-mini', label: 'GPT-4o Mini' },
]

function getHistoryKey(projectPath: string) {
  return `chat-history:${projectPath}`
}

function loadHistory(projectPath: string): Message[] {
  try {
    const raw = localStorage.getItem(getHistoryKey(projectPath))
    return raw ? (JSON.parse(raw) as Message[]) : []
  } catch {
    return []
  }
}

function saveHistory(projectPath: string, messages: Message[]) {
  localStorage.setItem(getHistoryKey(projectPath), JSON.stringify(messages))
}

interface ChatSidebarProps {
  isOpen: boolean
  onClose: () => void
  projectPath: string
  currentFilePath?: string
  currentFileContent?: string
}

export function ChatSidebar({
  isOpen,
  onClose,
  projectPath,
  currentFilePath,
  currentFileContent,
}: ChatSidebarProps) {
  const [messages, setMessages] = useState<Message[]>(() => loadHistory(projectPath))
  const [input, setInput] = useState('')
  const [model, setModel] = useState(MODELS[0].id)
  const [loading, setLoading] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  useEffect(() => {
    saveHistory(projectPath, messages)
  }, [messages, projectPath])

  const send = useCallback(async (text: string) => {
    if (!text.trim() || !window.ai) return
    setInput('')
    setLoading(true)

    const userMsg: Message = { role: 'user', content: text }
    const next = [...messages, userMsg]
    setMessages(next)

    try {
      const resp = await window.ai.chat(next, model)
      setMessages((prev) => [...prev, { role: 'assistant', content: resp.content }])
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { role: 'assistant', content: `Error: ${(err as Error).message}` },
      ])
    } finally {
      setLoading(false)
    }
  }, [messages, model])

  const attachFile = useCallback(() => {
    if (!currentFilePath || !currentFileContent) return
    const context = `File: \`${currentFilePath}\`\n\`\`\`\n${currentFileContent}\n\`\`\``
    setInput((prev) => (prev ? `${prev}\n\n${context}` : context))
  }, [currentFilePath, currentFileContent])

  const clearHistory = useCallback(() => {
    setMessages([])
    saveHistory(projectPath, [])
  }, [projectPath])

  return (
    <div
      className={cn(
        'flex flex-col h-full w-80 bg-zinc-900 border-l border-zinc-800',
        'transition-all duration-200',
        isOpen ? 'translate-x-0' : 'translate-x-full'
      )}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800 shrink-0">
        <span className="text-sm font-medium text-zinc-200">AI Assistant</span>
        <div className="flex items-center gap-1">
          <button
            onClick={clearHistory}
            className="p-1.5 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800 rounded transition-colors"
            title="Clear history"
          >
            <Trash2 size={14} />
          </button>
          <button
            onClick={onClose}
            className="p-1.5 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800 rounded transition-colors"
          >
            <ChevronRight size={14} />
          </button>
        </div>
      </div>

      {/* Model selector */}
      <div className="px-3 py-2 border-b border-zinc-800 shrink-0">
        <select
          value={model}
          onChange={(e) => setModel(e.target.value)}
          className="w-full bg-zinc-800 text-zinc-300 text-xs rounded px-2 py-1.5 border border-zinc-700 focus:outline-none focus:border-zinc-500"
        >
          {MODELS.map((m) => (
            <option key={m.id} value={m.id}>{m.label}</option>
          ))}
        </select>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-3 py-3 space-y-3 min-h-0">
        {messages.length === 0 && (
          <p className="text-xs text-zinc-600 text-center pt-4">
            Ask anything about your project.
          </p>
        )}
        {messages.map((msg, i) => (
          <div
            key={i}
            className={cn(
              'max-w-full rounded-lg px-3 py-2 text-sm leading-relaxed',
              msg.role === 'user'
                ? 'bg-zinc-800 text-zinc-100 ml-4'
                : 'bg-zinc-950 text-zinc-300 mr-4'
            )}
          >
            <pre className="whitespace-pre-wrap font-sans break-words">{msg.content}</pre>
          </div>
        ))}
        {loading && (
          <div className="bg-zinc-950 rounded-lg px-3 py-2 mr-4">
            <span className="text-zinc-500 text-xs animate-pulse">Thinking...</span>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="px-3 py-3 border-t border-zinc-800 shrink-0 space-y-2">
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              send(input)
            }
          }}
          placeholder="Ask AI... (Enter to send, Shift+Enter for newline)"
          rows={3}
          className="w-full bg-zinc-800 text-zinc-200 text-xs rounded px-3 py-2 border border-zinc-700 focus:outline-none focus:border-zinc-500 resize-none placeholder-zinc-600"
        />
        <div className="flex items-center justify-between">
          <button
            onClick={attachFile}
            disabled={!currentFilePath}
            className="flex items-center gap-1.5 text-xs text-zinc-500 hover:text-zinc-300 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title="Attach current file as context"
          >
            <Paperclip size={12} />
            Attach file
          </button>
          <button
            onClick={() => send(input)}
            disabled={loading || !input.trim()}
            className="flex items-center gap-1.5 bg-zinc-700 hover:bg-zinc-600 disabled:opacity-40 disabled:cursor-not-allowed text-zinc-200 text-xs px-3 py-1.5 rounded transition-colors"
          >
            <Send size={12} />
            Send
          </button>
        </div>
      </div>
    </div>
  )
}
