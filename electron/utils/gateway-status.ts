import type { GatewayStatus } from '../../src/lib/types'
import { loadAppSettings, normalizeGatewayUrl } from './app-settings'

function isLocalGatewayUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase()
    return host === 'localhost' || host === '127.0.0.1' || host === '::1'
  } catch {
    return false
  }
}

export async function getGatewayStatus(url?: string): Promise<GatewayStatus> {
  const gatewayUrl = normalizeGatewayUrl(url)

  try {
    const response = await fetch(`${gatewayUrl}/health`)
    if (!response.ok) {
      return {
        url: gatewayUrl,
        state: 'offline',
        reachable: false,
        error: `Gateway health returned ${response.status}`,
      }
    }

    return {
      url: gatewayUrl,
      state: isLocalGatewayUrl(gatewayUrl) ? 'local' : 'remote',
      reachable: true,
      error: null,
    }
  } catch (error) {
    return {
      url: gatewayUrl,
      state: 'offline',
      reachable: false,
      error: error instanceof Error ? error.message : 'Gateway unavailable',
    }
  }
}

export async function getSavedGatewayStatus(): Promise<GatewayStatus> {
  const settings = await loadAppSettings()
  return getGatewayStatus(settings.gatewayUrl)
}
