import { access } from 'fs/promises'
import { constants } from 'fs'
import { execFile } from 'child_process'
import { promisify } from 'util'

const execFileAsync = promisify(execFile)

export interface ToolPaths {
  kicadCli: string | null
  kicadGui: string | null
  freecadCmd: string | null
  freecadGui: string | null
  platformio: string | null
  git: string | null
}

const KICAD_PATHS: Record<string, string[]> = {
  darwin: ['/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli', '/Applications/KiCad/KiCad.app/Contents/MacOS/kicad'],
  linux: ['/usr/bin/kicad-cli', '/usr/bin/kicad'],
  win32: ['C:\\Program Files\\KiCad\\8.0\\bin\\kicad-cli.exe', 'C:\\Program Files\\KiCad\\8.0\\bin\\kicad.exe'],
}

const FREECAD_PATHS: Record<string, string[]> = {
  darwin: ['/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd', '/Applications/FreeCAD.app/Contents/MacOS/FreeCAD'],
  linux: ['/usr/bin/freecadcmd', '/usr/bin/freecad'],
  win32: ['C:\\Program Files\\FreeCAD 1.0\\bin\\FreeCADCmd.exe', 'C:\\Program Files\\FreeCAD 1.0\\bin\\FreeCAD.exe'],
}

async function findBinary(candidates: string[]): Promise<string | null> {
  for (const p of candidates) {
    try { await access(p, constants.X_OK); return p } catch {}
  }
  return null
}

async function whichBinary(name: string): Promise<string | null> {
  try {
    const cmd = process.platform === 'win32' ? 'where' : 'which'
    const { stdout } = await execFileAsync(cmd, [name])
    return stdout.trim() || null
  } catch { return null }
}

export async function detectTools(): Promise<ToolPaths> {
  const platform = process.platform
  const kicadCandidates = KICAD_PATHS[platform] ?? []
  const freecadCandidates = FREECAD_PATHS[platform] ?? []

  const [kicadCli, freecadCmd, platformio, git] = await Promise.all([
    findBinary(kicadCandidates.filter(p => p.includes('cli') || p.includes('Cmd'))).then(r => r ?? whichBinary('kicad-cli')),
    findBinary(freecadCandidates.filter(p => p.includes('Cmd') || p.includes('cmd'))).then(r => r ?? whichBinary('freecadcmd')),
    whichBinary('pio').then(r => r ?? whichBinary('platformio')),
    whichBinary('git'),
  ])

  const kicadGui = await findBinary(kicadCandidates.filter(p => !p.includes('cli') && !p.includes('Cmd')))
  const freecadGui = await findBinary(freecadCandidates.filter(p => !p.includes('Cmd') && !p.includes('cmd')))

  return { kicadCli, kicadGui, freecadCmd, freecadGui, platformio, git }
}
