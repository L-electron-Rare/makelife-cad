import { useEffect, useRef, useState } from 'react'
import { useAIStore } from '@/stores/ai'
import { useProjectStore } from '@/stores/project'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ScrollArea } from '@/components/ui/scroll-area'
import { Badge } from '@/components/ui/badge'
import { Bot, Send, Trash2, Wifi, WifiOff, Cable } from 'lucide-react'
import { cn } from '@/lib/utils'

export default function AI() {
  const { messages, isStreaming, isConnected, sendMessage, checkConnection, clearHistory } = useAIStore()
  const appSettings = useProjectStore((s) => s.appSettings)
  const loadAppSettings = useProjectStore((s) => s.loadAppSettings)
  const [input, setInput] = useState('')
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    void checkConnection()
    void loadAppSettings()
  }, [checkConnection, loadAppSettings])
  useEffect(() => { scrollRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  const handleSend = () => {
    if (!input.trim() || isStreaming) return
    sendMessage(input.trim())
    setInput('')
  }

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between gap-3 p-3 border-b">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <Bot size={18} />
            <span className="font-medium text-sm">AI Assistant</span>
            <Badge variant={isConnected ? 'default' : 'destructive'} className="text-xs">
              {isConnected ? <><Wifi size={10} className="mr-1" /> Connected</> : <><WifiOff size={10} className="mr-1" /> Offline</>}
            </Badge>
          </div>
          <div className="mt-1 flex items-center gap-2 text-[11px] text-muted-foreground">
            <Cable size={12} />
            <span className="font-mono truncate" title={appSettings?.gatewayUrl}>
              Factory gateway: {appSettings?.gatewayUrl ?? 'loading...'}
            </span>
          </div>
        </div>
        <Button variant="ghost" size="sm" onClick={clearHistory}><Trash2 size={14} /></Button>
      </div>

      <ScrollArea className="flex-1 p-4">
        <div className="space-y-4 max-w-3xl mx-auto">
          {messages.length === 0 && (
            <div className="text-center text-muted-foreground py-16">
              <Bot size={48} className="mx-auto mb-4 opacity-30" />
              <p>Ask about your hardware design, schematics, or firmware</p>
              <p className="text-xs mt-1">Powered by mascarade-core</p>
            </div>
          )}
          {messages.map(msg => (
            <div key={msg.id} className={cn('flex', msg.role === 'user' ? 'justify-end' : 'justify-start')}>
              <div className={cn('max-w-[80%] rounded-lg px-4 py-2 text-sm',
                msg.role === 'user' ? 'bg-primary text-primary-foreground' : 'bg-secondary')}>
                <p className="whitespace-pre-wrap">{msg.content}</p>
              </div>
            </div>
          ))}
          {isStreaming && (
            <div className="flex justify-start">
              <div className="bg-secondary rounded-lg px-4 py-2 text-sm animate-pulse">Thinking...</div>
            </div>
          )}
          <div ref={scrollRef} />
        </div>
      </ScrollArea>

      <div className="p-3 border-t">
        <div className="flex gap-2 max-w-3xl mx-auto">
          <Input placeholder="Ask about your design..." value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleSend()}
            disabled={isStreaming} />
          <Button onClick={handleSend} disabled={isStreaming || !input.trim()}><Send size={14} /></Button>
        </div>
      </div>
    </div>
  )
}
