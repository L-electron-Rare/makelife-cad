import { processManager } from '../utils/process-manager'
import { detectTools } from '../utils/detect-tools'

let cachedGui: string | null = null

async function getKicadGui(): Promise<string> {
  if (cachedGui) return cachedGui
  const tools = await detectTools()
  if (!tools.kicadGui) throw new Error('KiCad not found')
  cachedGui = tools.kicadGui
  return cachedGui
}

export async function launchKicad(filePath: string) {
  const kicad = await getKicadGui()
  processManager.launch(`kicad-${filePath}`, kicad, [filePath], `KiCad: ${filePath.split('/').pop()}`)
}
