import { execFile } from 'child_process'
import { promisify } from 'util'
import { processManager } from '../utils/process-manager'
import { detectTools } from '../utils/detect-tools'

const execFileAsync = promisify(execFile)

let cachedGui: string | null = null
let cachedCli: string | null = null

async function getKicadGui(): Promise<string> {
  if (cachedGui) return cachedGui
  const tools = await detectTools()
  if (!tools.kicadGui) throw new Error('KiCad not found')
  cachedGui = tools.kicadGui
  return cachedGui
}

async function getKicadCli(): Promise<string> {
  if (cachedCli) return cachedCli
  const tools = await detectTools()
  if (!tools.kicadCli) throw new Error('kicad-cli not found')
  cachedCli = tools.kicadCli
  return cachedCli
}

export async function launchKicad(filePath: string) {
  const kicad = await getKicadGui()
  processManager.launch(`kicad-${filePath}`, kicad, [filePath], `KiCad: ${filePath.split('/').pop()}`)
}

export async function runErc(schPath: string, outputDir: string) {
  const cli = await getKicadCli()
  const outFile = `${outputDir}/erc.json`
  try {
    await execFileAsync(cli, ['sch', 'erc', '--format', 'json', '--output', outFile, schPath], { timeout: 60000 })
    const fs = await import('fs/promises')
    return { ok: true, report: await fs.readFile(outFile, 'utf-8') }
  } catch (err: any) {
    return { ok: false, report: err.stderr || err.message }
  }
}

export async function runDrc(pcbPath: string, outputDir: string) {
  const cli = await getKicadCli()
  const outFile = `${outputDir}/drc.json`
  try {
    await execFileAsync(cli, ['pcb', 'drc', '--format', 'json', '--output', outFile, pcbPath], { timeout: 60000 })
    const fs = await import('fs/promises')
    return { ok: true, report: await fs.readFile(outFile, 'utf-8') }
  } catch (err: any) {
    return { ok: false, report: err.stderr || err.message }
  }
}

export async function exportSchematicSvg(schPath: string, outputDir: string) {
  const cli = await getKicadCli()
  await execFileAsync(cli, ['sch', 'export', 'svg', '--output', outputDir, schPath], { timeout: 60000 })
}

export async function exportGerbers(pcbPath: string, outputDir: string) {
  const cli = await getKicadCli()
  await execFileAsync(cli, ['pcb', 'export', 'gerbers', '--output', outputDir, pcbPath], { timeout: 60000 })
}

export async function exportBom(schPath: string, outputPath: string) {
  const cli = await getKicadCli()
  await execFileAsync(cli, ['sch', 'export', 'bom', '--output', outputPath, schPath], { timeout: 60000 })
}
