import { app } from 'electron'
import path from 'path'
import { mkdir, readFile, writeFile } from 'fs/promises'

export type AppSettings = {
  gatewayUrl: string
}

const DEFAULT_GATEWAY_URL = (process.env.MAKELIFE_CAD_URL ?? 'http://localhost:8001').replace(/\/$/, '')

function settingsPath(): string {
  return path.join(app.getPath('userData'), 'settings.json')
}

export function defaultAppSettings(): AppSettings {
  return {
    gatewayUrl: DEFAULT_GATEWAY_URL,
  }
}

export function normalizeGatewayUrl(url?: string): string {
  const value = (url ?? DEFAULT_GATEWAY_URL).trim()
  return (value || DEFAULT_GATEWAY_URL).replace(/\/$/, '')
}

export async function loadAppSettings(): Promise<AppSettings> {
  try {
    const raw = await readFile(settingsPath(), 'utf-8')
    const parsed = JSON.parse(raw) as Partial<AppSettings>
    return {
      gatewayUrl: normalizeGatewayUrl(parsed.gatewayUrl),
    }
  } catch {
    return defaultAppSettings()
  }
}

export async function saveAppSettings(partial: Partial<AppSettings>): Promise<AppSettings> {
  const current = await loadAppSettings()
  const next: AppSettings = {
    gatewayUrl: normalizeGatewayUrl(partial.gatewayUrl ?? current.gatewayUrl),
  }

  await mkdir(path.dirname(settingsPath()), { recursive: true })
  await writeFile(settingsPath(), JSON.stringify(next, null, 2), 'utf-8')
  return next
}
