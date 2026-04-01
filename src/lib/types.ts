export interface MakelifeConfig {
  name: string
  version: string
  paths: {
    hardware?: string
    mechanical?: string
    firmware?: string
    docs?: string
  }
  tools: Record<string, string>
  remotes?: { github?: string }
}

export interface FileEntry {
  name: string
  path: string
  isDirectory: boolean
}

export interface ToolPaths {
  kicadCli: string | null
  kicadGui: string | null
  freecadCmd: string | null
  freecadGui: string | null
  platformio: string | null
  git: string | null
}
