import { create } from 'zustand'
import type { MakelifeConfig, ToolPaths } from '@/lib/types'

interface ProjectState {
  projectPath: string | null
  config: MakelifeConfig | null
  toolPaths: ToolPaths | null
  recentProjects: string[]
  openProject: (path: string) => Promise<void>
  detectTools: () => Promise<void>
  closeProject: () => void
}

export const useProjectStore = create<ProjectState>((set, get) => ({
  projectPath: null,
  config: null,
  toolPaths: null,
  recentProjects: [],

  openProject: async (projectPath: string) => {
    const config = await window.electronAPI.getProjectConfig(projectPath)
    set({ projectPath, config })
  },

  detectTools: async () => {
    const toolPaths = await window.electronAPI.detectTools()
    set({ toolPaths })
  },

  closeProject: () => set({ projectPath: null, config: null }),
}))
