import { create } from 'zustand'

interface Message { id: string; role: 'user' | 'assistant'; content: string; timestamp: number }

interface AIState {
  messages: Message[]
  isStreaming: boolean
  isConnected: boolean
  sendMessage: (content: string) => Promise<void>
  checkConnection: () => Promise<void>
  clearHistory: () => void
}

export const useAIStore = create<AIState>((set, get) => ({
  messages: [],
  isStreaming: false,
  isConnected: false,

  checkConnection: async () => {
    const ok = await window.electronAPI.invoke('mascarade:health')
    set({ isConnected: ok })
  },

  sendMessage: async (content) => {
    const userMsg: Message = { id: crypto.randomUUID(), role: 'user', content, timestamp: Date.now() }
    set(s => ({ messages: [...s.messages, userMsg], isStreaming: true }))
    try {
      const allMsgs = get().messages.map(m => ({ role: m.role, content: m.content }))
      const response = await window.electronAPI.invoke('mascarade:chat', allMsgs)
      const assistantMsg: Message = { id: crypto.randomUUID(), role: 'assistant', content: response, timestamp: Date.now() }
      set(s => ({ messages: [...s.messages, assistantMsg], isStreaming: false }))
    } catch (err: any) {
      const errorMsg: Message = { id: crypto.randomUUID(), role: 'assistant', content: `Error: ${err.message}`, timestamp: Date.now() }
      set(s => ({ messages: [...s.messages, errorMsg], isStreaming: false }))
    }
  },

  clearHistory: () => set({ messages: [] }),
}))
