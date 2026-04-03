import { spawn } from 'child_process'
import { access } from 'fs/promises'
import { mkdtempSync, writeFileSync } from 'fs'
import { tmpdir } from 'os'
import path from 'path'
import { processManager } from '../utils/process-manager'
import type { FreeCADExportResult, FreeCADStatusSummary, FreeCADRuntimeStatus } from '../../src/lib/types'

const DEFAULT_GATEWAY_URL = (process.env.MAKELIFE_CAD_URL ?? 'http://localhost:8001').replace(/\/$/, '')
const FREECAD_TIMEOUT_MS = Math.max(5, Number(process.env.FREECAD_TIMEOUT ?? '120')) * 1000
const TARGET_VERSION = '1.1.0'

type FreecadExportOptions = {
  inputPath: string
  format: 'step' | 'stl'
  outputDir?: string
  gatewayUrl?: string
}

type ProcessResult = {
  exitCode: number
  stdout: string
  stderr: string
}

const UNAVAILABLE_STATUS: FreeCADRuntimeStatus = {
  status: 'unavailable',
  installed: false,
  version: null,
  compatible: false,
  path: null,
  source: 'unavailable',
  preferredExportMode: 'unavailable',
}

function parseVersion(raw: string): string | null {
  const match = raw.match(/\d+\.\d+\.\d+/)
  return match ? match[0] : null
}

function isCompatible(version: string | null): boolean {
  return Boolean(version && version.startsWith('1.1.'))
}

function normalizeGatewayUrl(url?: string): string {
  return (url ?? DEFAULT_GATEWAY_URL).trim().replace(/\/$/, '') || DEFAULT_GATEWAY_URL
}

function isLocalGateway(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase()
    return host === 'localhost' || host === '127.0.0.1' || host === '::1'
  } catch {
    return false
  }
}

async function pathExists(target: string): Promise<boolean> {
  try {
    await access(target)
    return true
  } catch {
    return false
  }
}

async function resolveExecutable(candidates: Array<string | null | undefined>): Promise<string | null> {
  for (const candidate of candidates) {
    if (!candidate) continue

    if (candidate.includes('/')) {
      if (await pathExists(candidate)) return candidate
      continue
    }

    const result = await runProcess('/usr/bin/which', [candidate], 5000).catch(() => null)
    const resolved = result?.stdout.trim()
    if (resolved) return resolved
  }

  return null
}

async function resolveFreecadApp(): Promise<string | null> {
  for (const candidate of [
    '/Applications/FreeCAD.app',
    '/Applications/FreeCAD 1.1.app',
  ]) {
    if (await pathExists(candidate)) return candidate
  }
  return null
}

async function runProcess(
  executable: string,
  args: string[],
  timeoutMs = FREECAD_TIMEOUT_MS
): Promise<ProcessResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, { stdio: ['ignore', 'pipe', 'pipe'] })
    processManager.register(child)

    let stdout = ''
    let stderr = ''
    let settled = false

    const timer = setTimeout(() => {
      if (settled) return
      settled = true
      child.kill('SIGTERM')
      reject(new Error(`Timed out after ${Math.round(timeoutMs / 1000)}s`))
    }, timeoutMs)

    child.stdout?.on('data', (chunk) => {
      stdout += chunk.toString()
    })

    child.stderr?.on('data', (chunk) => {
      stderr += chunk.toString()
    })

    child.on('error', (error) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      reject(error)
    })

    child.on('exit', (code) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve({
        exitCode: code ?? 1,
        stdout,
        stderr,
      })
    })
  })
}

async function runFreecadScript(
  executable: string,
  script: string,
  args: string[]
): Promise<ProcessResult> {
  const tempDir = mkdtempSync(path.join(tmpdir(), 'freecad-bridge-'))
  const scriptPath = path.join(tempDir, 'script.py')
  writeFileSync(scriptPath, script, 'utf-8')
  return runProcess(executable, ['-c', scriptPath, ...args])
}

async function detectLocalStatus(): Promise<FreeCADRuntimeStatus> {
  const command = await resolveExecutable([
    process.env.FREECAD_CMD,
    '/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd',
    '/Applications/FreeCAD 1.1.app/Contents/MacOS/FreeCADCmd',
    'FreeCADCmd',
    'freecadcmd',
  ])

  if (!command) return UNAVAILABLE_STATUS

  try {
    const result = await runFreecadScript(
      command,
      [
        'import FreeCAD',
        'version = FreeCAD.Version()',
        'print(".".join(str(part) for part in version[:3]))',
      ].join('\n'),
      []
    )

    const version = parseVersion(`${result.stdout}\n${result.stderr}`)
    return {
      status: isCompatible(version) ? 'available' : 'incompatible',
      installed: true,
      version,
      compatible: isCompatible(version),
      path: command,
      source: command === process.env.FREECAD_CMD
        ? 'env'
        : command.includes('/Applications/')
          ? 'app_bundle'
          : 'path',
      preferredExportMode: 'local',
      error: result.exitCode === 0 ? null : result.stderr.trim() || null,
    }
  } catch (error) {
    return {
      status: 'unavailable',
      installed: true,
      version: null,
      compatible: false,
      path: command,
      source: command.includes('/Applications/') ? 'app_bundle' : 'path',
      preferredExportMode: 'unavailable',
      error: error instanceof Error ? error.message : 'FreeCAD probe failed',
    }
  }
}

async function detectGatewayStatus(gatewayUrl: string): Promise<FreeCADRuntimeStatus | null> {
  if (!isLocalGateway(gatewayUrl)) return null

  try {
    const response = await fetch(`${gatewayUrl}/freecad/status`)
    if (!response.ok) {
      return {
        status: 'offline',
        installed: false,
        version: null,
        compatible: false,
        path: null,
        source: 'gateway',
        preferredExportMode: 'local',
        error: `Gateway error ${response.status}`,
      }
    }

    return await response.json() as FreeCADRuntimeStatus
  } catch (error) {
    return {
      status: 'offline',
      installed: false,
      version: null,
      compatible: false,
      path: null,
      source: 'gateway',
      preferredExportMode: 'local',
      error: error instanceof Error ? error.message : 'Gateway unavailable',
    }
  }
}

function chooseMode(
  local: FreeCADRuntimeStatus,
  gateway: FreeCADRuntimeStatus | null,
  gatewayUrl: string
): FreeCADStatusSummary['chosenMode'] {
  if (!local.compatible) return 'unavailable'
  if (gateway?.compatible && isLocalGateway(gatewayUrl)) return 'gateway'
  return 'local'
}

async function exportLocally(
  opts: FreecadExportOptions,
  local: FreeCADRuntimeStatus
): Promise<FreeCADExportResult> {
  const executable = local.path
  if (!executable) {
    return {
      ok: false,
      mode: 'unavailable',
      error: 'FreeCAD command is unavailable.',
      versionUsed: local.version,
      source: local.source,
    }
  }

  const outDir = opts.outputDir ?? mkdtempSync(path.join(tmpdir(), 'freecad-export-'))
  const outputPath = path.join(
    outDir,
    `${path.parse(opts.inputPath).name}.${opts.format === 'step' ? 'step' : 'stl'}`
  )

  const script = [
    'import FreeCAD, Part, Mesh, sys',
    'inp, outp, fmt = sys.argv[1], sys.argv[2], sys.argv[3]',
    'doc = FreeCAD.openDocument(inp)',
    "objs = [obj for obj in doc.Objects if hasattr(obj, 'Shape') or hasattr(obj, 'Mesh')]",
    "if not objs: raise RuntimeError('No exportable objects found in document')",
    "Mesh.export(objs, outp) if fmt == 'stl' else Part.export(objs, outp)",
    'doc.close()',
    'print(outp)',
  ].join('\n')

  try {
    const result = await runFreecadScript(executable, script, [opts.inputPath, outputPath, opts.format])
    return {
      ok: result.exitCode === 0,
      outputPath: result.exitCode === 0 ? outputPath : undefined,
      stdout: result.stdout,
      stderr: result.stderr,
      mode: 'local',
      versionUsed: local.version,
      source: local.source,
      error: result.exitCode === 0 ? undefined : (result.stderr.trim() || `FreeCAD exited with ${result.exitCode}`),
    }
  } catch (error) {
    return {
      ok: false,
      mode: 'local',
      versionUsed: local.version,
      source: local.source,
      error: error instanceof Error ? error.message : 'Local export failed',
    }
  }
}

async function exportViaGateway(opts: FreecadExportOptions, gatewayUrl: string): Promise<FreeCADExportResult> {
  const response = await fetch(`${gatewayUrl}/freecad/export`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      input_path: opts.inputPath,
      format: opts.format,
      output_dir: opts.outputDir,
    }),
  })

  const raw = await response.text()
  if (!response.ok) {
    throw new Error(raw || `Gateway export failed with ${response.status}`)
  }

  const payload = JSON.parse(raw) as {
    status: string
    output_path?: string
    stdout?: string
    stderr?: string
    version_used?: string | null
    source?: string | null
  }

  return {
    ok: payload.status === 'ok',
    outputPath: payload.output_path,
    stdout: payload.stdout,
    stderr: payload.stderr,
    mode: 'gateway',
    versionUsed: payload.version_used ?? null,
    source: payload.source ?? 'gateway',
    error: payload.status === 'ok' ? undefined : (payload.stderr || 'Gateway export failed'),
  }
}

export async function getFreecadStatus(settings?: { gatewayUrl?: string }): Promise<FreeCADStatusSummary> {
  const gatewayUrl = normalizeGatewayUrl(settings?.gatewayUrl)
  const local = await detectLocalStatus()
  const gateway = await detectGatewayStatus(gatewayUrl)

  return {
    gatewayUrl,
    local,
    gateway,
    chosenMode: chooseMode(local, gateway, gatewayUrl),
  }
}

export async function exportModel(opts: FreecadExportOptions): Promise<FreeCADExportResult> {
  const gatewayUrl = normalizeGatewayUrl(opts.gatewayUrl)
  const status = await getFreecadStatus({ gatewayUrl })

  if (status.chosenMode === 'unavailable') {
    return {
      ok: false,
      mode: 'unavailable',
      error: status.local.error
        ?? `FreeCAD ${TARGET_VERSION} requires a compatible local 1.1.x runtime.`,
      versionUsed: status.local.version,
      source: status.local.source,
    }
  }

  if (status.chosenMode === 'gateway') {
    try {
      return await exportViaGateway(opts, gatewayUrl)
    } catch (error) {
      const fallback = await exportLocally(opts, status.local)
      fallback.fallbackReason = error instanceof Error ? error.message : 'Gateway export failed'
      return fallback
    }
  }

  return exportLocally(opts, status.local)
}

export async function launchFreecad(filePath: string): Promise<{ ok: boolean; error?: string }> {
  const appPath = await resolveFreecadApp()

  return new Promise((resolve) => {
    const args = appPath ? ['-a', appPath, filePath] : ['-a', 'FreeCAD', filePath]
    const child = spawn('open', args, { stdio: 'ignore' })
    processManager.register(child)
    child.on('error', (err) => resolve({ ok: false, error: err.message }))
    child.on('exit', (code) => resolve({
      ok: code === 0,
      error: code === 0 ? undefined : `exit ${code}`,
    }))
  })
}
