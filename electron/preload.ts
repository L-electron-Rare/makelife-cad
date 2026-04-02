import { contextBridge, ipcRenderer } from 'electron'

contextBridge.exposeInMainWorld('electronAPI', {
  platform: process.platform,
  // File system
  readDir: (dirPath: string) => ipcRenderer.invoke('fs:readDir', dirPath),
  readFile: (filePath: string) => ipcRenderer.invoke('fs:readFile', filePath),
  openDirDialog: () => ipcRenderer.invoke('dialog:openDir'),
  // Project
  getProjectConfig: (projectPath: string) => ipcRenderer.invoke('project:getConfig', projectPath),
  createProject: (name: string, path: string) => ipcRenderer.invoke('project:create', name, path),
  // Tools
  detectTools: () => ipcRenderer.invoke('tools:detect'),
  // Generic invoke for future use
  invoke: (channel: string, ...args: unknown[]) => ipcRenderer.invoke(channel, ...args),
})

contextBridge.exposeInMainWorld('terminal', {
  spawn: (preset: string, cwd?: string) =>
    ipcRenderer.invoke('terminal:spawn', preset, cwd),
  write: (id: string, data: string) =>
    ipcRenderer.invoke('terminal:write', id, data),
  resize: (id: string, cols: number, rows: number) =>
    ipcRenderer.invoke('terminal:resize', id, cols, rows),
  kill: (id: string) =>
    ipcRenderer.invoke('terminal:kill', id),
  onData: (id: string, callback: (data: string) => void) => {
    ipcRenderer.on(`terminal:data:${id}`, (_event, data) => callback(data))
  },
  onExit: (id: string, callback: () => void) => {
    ipcRenderer.once(`terminal:exit:${id}`, () => callback())
  },
  removeDataListener: (id: string) => {
    ipcRenderer.removeAllListeners(`terminal:data:${id}`)
    ipcRenderer.removeAllListeners(`terminal:exit:${id}`)
  },
})

contextBridge.exposeInMainWorld('ai', {
  chat: (
    messages: Array<{ role: string; content: string }>,
    model?: string
  ) => ipcRenderer.invoke('ai:chat', messages, model),
  reviewSchematic: (filePath: string, focus?: string[]) =>
    ipcRenderer.invoke('ai:review-schematic', filePath, focus),
  suggestComponent: (
    description: string,
    constraints?: Record<string, string>
  ) => ipcRenderer.invoke('ai:suggest-component', description, constraints),
})
