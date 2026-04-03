import { create } from 'zustand'
import type { AppSettings, GatewayStatus, MakelifeConfig, ToolPaths } from '@/lib/types'

interface ProjectState {
  projectPath: string | null
  config: MakelifeConfig | null
  toolPaths: ToolPaths | null
  appSettings: AppSettings | null
  gatewayStatus: GatewayStatus | null
  recentProjects: string[]
  openProject: (path: string) => Promise<void>
  detectTools: () => Promise<void>
  loadAppSettings: () => Promise<void>
  updateAppSettings: (patch: Partial<AppSettings>) => Promise<void>
  refreshGatewayStatus: () => Promise<void>
  closeProject: () => void
}

export const useProjectStore = create<ProjectState>((set, get) => ({
  projectPath: null,
  config: null,
  toolPaths: null,
  appSettings: null,
  gatewayStatus: null,
  recentProjects: [],

  openProject: async (projectPath: string) => {
    const config = await window.electronAPI.getProjectConfig(projectPath)
    set({ projectPath, config })
  },

  detectTools: async () => {
    const toolPaths = await window.electronAPI.detectTools()
    set({ toolPaths })
  },

  loadAppSettings: async () => {
    const appSettings = await window.electronAPI.invoke('settings:get') as AppSettings
    const gatewayStatus = await window.electronAPI.invoke('settings:getGatewayStatus') as GatewayStatus
    set({ appSettings, gatewayStatus })
  },

  updateAppSettings: async (patch) => {
    const appSettings = await window.electronAPI.invoke('settings:update', patch) as AppSettings
    const gatewayStatus = await window.electronAPI.invoke('settings:getGatewayStatus') as GatewayStatus
    set({ appSettings, gatewayStatus })
  },

  refreshGatewayStatus: async () => {
    const gatewayStatus = await window.electronAPI.invoke('settings:getGatewayStatus') as GatewayStatus
    set({ gatewayStatus })
  },

  closeProject: () => set({ projectPath: null, config: null }),
}))
