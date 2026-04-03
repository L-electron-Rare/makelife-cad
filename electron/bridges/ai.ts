import { ipcMain } from 'electron'
import { loadAppSettings } from '../utils/app-settings'

const LIFE_CORE_URL = process.env.LIFE_CORE_URL ?? 'http://localhost:8000'
const DEFAULT_AI_MODEL = process.env.DEFAULT_AI_MODEL ?? 'openai/qwen-14b-awq'

export interface Message {
  role: 'user' | 'assistant' | 'system'
  content: string
}

export interface ChatResponse {
  content: string
  model: string
}

export interface ReviewIssue {
  severity: 'error' | 'warning' | 'info'
  message: string
  suggestion: string
}

export interface ReviewResponse {
  issues: ReviewIssue[]
}

export interface SuggestedComponent {
  name: string
  value: string
  footprint: string
  reason: string
}

export interface SuggestResponse {
  components: SuggestedComponent[]
}

async function cadGatewayUrl(): Promise<string> {
  const settings = await loadAppSettings()
  return settings.gatewayUrl
}

export async function chat(messages: Message[], model?: string): Promise<ChatResponse> {
  const response = await fetch(`${LIFE_CORE_URL}/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ messages, model: model ?? DEFAULT_AI_MODEL }),
  })
  if (!response.ok) {
    throw new Error(`life-core /chat error: ${response.status} ${await response.text()}`)
  }
  return response.json() as Promise<ChatResponse>
}

export async function reviewSchematic(
  filePath: string,
  focus?: string[]
): Promise<ReviewResponse> {
  const gatewayUrl = await cadGatewayUrl()
  const response = await fetch(`${gatewayUrl}/ai/schematic-review`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ file_path: filePath, focus }),
  })
  if (!response.ok) {
    throw new Error(`makelife-cad /ai/schematic-review error from ${gatewayUrl}: ${response.status} ${await response.text()}`)
  }
  return response.json() as Promise<ReviewResponse>
}

export async function suggestComponent(
  description: string,
  constraints?: Record<string, string>
): Promise<SuggestResponse> {
  const gatewayUrl = await cadGatewayUrl()
  const response = await fetch(`${gatewayUrl}/ai/component-suggest`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ description, constraints }),
  })
  if (!response.ok) {
    throw new Error(`makelife-cad /ai/component-suggest error from ${gatewayUrl}: ${response.status} ${await response.text()}`)
  }
  return response.json() as Promise<SuggestResponse>
}

export function registerAiHandlers(): void {
  ipcMain.handle('ai:chat', (_event, messages: Message[], model?: string) =>
    chat(messages, model)
  )

  ipcMain.handle('ai:review-schematic', (_event, filePath: string, focus?: string[]) =>
    reviewSchematic(filePath, focus)
  )

  ipcMain.handle('ai:suggest-component', (
    _event,
    description: string,
    constraints?: Record<string, string>
  ) =>
    suggestComponent(description, constraints)
  )
}
