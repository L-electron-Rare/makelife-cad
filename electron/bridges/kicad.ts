import { spawn } from 'child_process'
import { processManager } from '../utils/process-manager'

function run(cmd: string, args: string[]) {
  return new Promise<{ ok: boolean; stdout?: string; stderr?: string }>((resolve) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] })
    processManager.register(child)
    let stdout = ''
    let stderr = ''
    child.stdout?.on('data', (d) => { stdout += d.toString() })
    child.stderr?.on('data', (d) => { stderr += d.toString() })
    child.on('error', (err) => resolve({ ok: false, stderr: err.message }))
    child.on('exit', (code) => resolve({ ok: code === 0, stdout, stderr }))
  })
}

export function launchKicad(filePath: string) {
  return run('open', ['-a', 'KiCad', filePath])
}

export function runErc(schPath: string, outputDir: string) {
  return run('kicad-cli', ['sch', 'erc', '--output', outputDir, schPath])
}

export function runDrc(pcbPath: string, outputDir: string) {
  return run('kicad-cli', ['pcb', 'drc', '--output', outputDir, pcbPath])
}

export function exportSchematicSvg(schPath: string, outputDir: string) {
  return run('kicad-cli', ['sch', 'export', 'svg', '--output', outputDir, schPath])
}

export function exportGerbers(pcbPath: string, outputDir: string) {
  return run('kicad-cli', ['pcb', 'export', 'gerbers', '--output', outputDir, pcbPath])
}

export function exportBom(schPath: string, outputPath: string) {
  return run('kicad-cli', ['sch', 'export', 'bom', '--output', outputPath, schPath])
}
