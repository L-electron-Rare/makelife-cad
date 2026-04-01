interface ElectronAPI {
  platform: string
  readDir: (dirPath: string) => Promise<Array<{ name: string; path: string; isDirectory: boolean }>>
  readFile: (filePath: string) => Promise<string>
  openDirDialog: () => Promise<string | null>
  getProjectConfig: (projectPath: string) => Promise<any>
  createProject: (name: string, path: string) => Promise<void>
  detectTools: () => Promise<import('./lib/types').ToolPaths>
  invoke: (channel: string, ...args: any[]) => Promise<any>
}

interface Window {
  electronAPI: ElectronAPI
}
