let baseUrl = 'http://localhost:8100'
let apiKey: string | undefined

export function configureMascarade(cfg: { baseUrl?: string; apiKey?: string }) {
  if (cfg.baseUrl) baseUrl = cfg.baseUrl
  if (cfg.apiKey) apiKey = cfg.apiKey
}

export async function chatSync(messages: Array<{ role: string; content: string }>): Promise<string> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (apiKey) headers['Authorization'] = `Bearer ${apiKey}`

  const response = await fetch(`${baseUrl}/v1/chat/completions`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ messages, stream: false }),
  })

  if (!response.ok) throw new Error(`Mascarade error: ${response.status} ${response.statusText}`)
  const data = await response.json()
  return data.choices?.[0]?.message?.content ?? 'No response'
}

export async function healthCheck(): Promise<boolean> {
  try {
    const r = await fetch(`${baseUrl}/health`, { method: 'GET', signal: AbortSignal.timeout(5000) })
    return r.ok
  } catch { return false }
}
