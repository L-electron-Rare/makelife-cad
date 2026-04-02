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
  terminal: {
    spawn: (preset: string, cwd?: string) => Promise<string>
    write: (id: string, data: string) => Promise<void>
    resize: (id: string, cols: number, rows: number) => Promise<void>
    kill: (id: string) => Promise<void>
    onData: (id: string, callback: (data: string) => void) => void
    onExit: (id: string, callback: () => void) => void
    removeDataListener: (id: string) => void
  }
  ai: {
    chat: (
      messages: Array<{ role: string; content: string }>,
      model?: string
    ) => Promise<{ content: string; model: string }>
    reviewSchematic: (
      filePath: string,
      focus?: string[]
    ) => Promise<{ issues: Array<{ severity: string; message: string; suggestion: string }> }>
    suggestComponent: (
      description: string,
      constraints?: Record<string, string>
    ) => Promise<{ components: Array<{ name: string; value: string; footprint: string; reason: string }> }>
  }
}
