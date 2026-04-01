import { processManager } from '../utils/process-manager'
import { detectTools } from '../utils/detect-tools'

let cachedGui: string | null = null

async function getFreecadGui(): Promise<string> {
  if (cachedGui) return cachedGui
  const tools = await detectTools()
  if (!tools.freecadGui) throw new Error('FreeCAD not found')
  cachedGui = tools.freecadGui
  return cachedGui
}

export async function launchFreecad(filePath: string) {
  const freecad = await getFreecadGui()
  processManager.launch(`freecad-${filePath}`, freecad, [filePath], `FreeCAD: ${filePath.split('/').pop()}`)
}
