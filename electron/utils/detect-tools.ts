import { execFile as execFileCb } from 'child_process'
import { access } from 'fs/promises'
import { promisify } from 'util'
import type { ToolPaths } from '../../src/lib/types'

const execFile = promisify(execFileCb)

async function resolveExecutable(candidate?: string | null): Promise<string | null> {
  if (!candidate) return null

  if (candidate.includes('/')) {
    try {
      await access(candidate)
      return candidate
    } catch {
      return null
    }
  }

  try {
    const { stdout } = await execFile('/usr/bin/which', [candidate])
    const resolved = stdout.trim()
    return resolved || null
  } catch {
    return null
  }
}

async function resolveFirst(candidates: Array<string | null | undefined>): Promise<string | null> {
  for (const candidate of candidates) {
    const resolved = await resolveExecutable(candidate)
    if (resolved) return resolved
  }
  return null
}

async function resolveDirectory(pathname: string): Promise<string | null> {
  try {
    await access(pathname)
    return pathname
  } catch {
    return null
  }
}

export async function detectTools(): Promise<ToolPaths> {
  const freecadCmd = await resolveFirst([
    process.env.FREECAD_CMD,
    '/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd',
    '/Applications/FreeCAD 1.1.app/Contents/MacOS/FreeCADCmd',
    'FreeCADCmd',
    'freecadcmd',
  ])

  const freecadGuiDir = await resolveFirst([
    '/Applications/FreeCAD.app/Contents/MacOS/FreeCAD',
    '/Applications/FreeCAD 1.1.app/Contents/MacOS/FreeCAD',
    'FreeCAD',
  ])

  const kicadGuiApp = await resolveDirectory('/Applications/KiCad/KiCad.app')
  const freecadGuiApp = await resolveDirectory('/Applications/FreeCAD.app')
    ?? await resolveDirectory('/Applications/FreeCAD 1.1.app')

  return {
    git: await resolveExecutable('git'),
    kicadCli: await resolveExecutable('kicad-cli'),
    kicadGui: kicadGuiApp ?? await resolveExecutable('kicad'),
    freecadCmd,
    freecadGui: freecadGuiApp ?? freecadGuiDir,
    platformio: await resolveExecutable('pio'),
    cmake: await resolveExecutable('cmake'),
    node: await resolveExecutable('node'),
    python3: await resolveExecutable('python3'),
  }
}
