import { spawn } from 'child_process'
import { processManager } from '../utils/process-manager'

export function healthCheck() {
  // placeholder: assume healthy
  return Promise.resolve({ ok: true })
}

export function chatSync(messages: any[]) {
  return Promise.resolve({ content: 'stubbed response', messages })
}

export function configureMascarade(_cfg: Record<string, unknown>) {
  // stub configuration
  return Promise.resolve({ ok: true })
}
