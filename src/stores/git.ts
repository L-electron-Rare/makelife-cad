import { create } from 'zustand'

interface GitState {
  currentBranch: string | null
  branches: string[]
  status: Array<{ filepath: string; status: string }>
  log: Array<{ oid: string; message: string; author: { name: string; email: string; timestamp: number } }>
  isLoading: boolean
  refresh: (dir: string) => Promise<void>
  stageFile: (dir: string, filepath: string) => Promise<void>
  commit: (dir: string, message: string) => Promise<void>
}

export const useGitStore = create<GitState>((set, get) => ({
  currentBranch: null,
  branches: [],
  status: [],
  log: [],
  isLoading: false,

  refresh: async (dir) => {
    set({ isLoading: true })
    const [currentBranch, branches, status, log] = await Promise.all([
      window.electronAPI.invoke('git:currentBranch', dir),
      window.electronAPI.invoke('git:branches', dir),
      window.electronAPI.invoke('git:status', dir),
      window.electronAPI.invoke('git:log', dir, 20),
    ])
    set({ currentBranch, branches, status, log, isLoading: false })
  },

  stageFile: async (dir, filepath) => {
    await window.electronAPI.invoke('git:add', dir, filepath)
    await get().refresh(dir)
  },

  commit: async (dir, message) => {
    await window.electronAPI.invoke('git:commit', dir, message, { name: 'MakeLife User', email: 'user@makelife.dev' })
    await get().refresh(dir)
  },
}))
