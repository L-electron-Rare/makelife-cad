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
  invoke: (channel: string, ...args: any[]) => ipcRenderer.invoke(channel, ...args),
})
