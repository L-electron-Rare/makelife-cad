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
  cmake: string | null
  node: string | null
  python3: string | null
}

export interface FreeCADDocument {
  name: string
  path: string
  relativePath: string
}

export interface FreeCADRuntimeStatus {
  status: string
  installed: boolean
  version: string | null
  compatible: boolean
  path: string | null
  source: string
  preferredExportMode: string
  error?: string | null
}

export interface FreeCADStatusSummary {
  gatewayUrl: string
  local: FreeCADRuntimeStatus
  gateway: FreeCADRuntimeStatus | null
  chosenMode: 'local' | 'gateway' | 'unavailable'
}

export interface FreeCADExportResult {
  ok: boolean
  outputPath?: string
  stdout?: string
  stderr?: string
  mode: 'local' | 'gateway' | 'unavailable'
  versionUsed?: string | null
  source?: string | null
  fallbackReason?: string
  error?: string
}

export interface AppSettings {
  gatewayUrl: string
}

export interface GatewayStatus {
  url: string
  state: 'local' | 'remote' | 'offline'
  reachable: boolean
  error?: string | null
}
