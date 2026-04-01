import { execFile } from 'child_process'
import { promisify } from 'util'
import { detectTools } from '../utils/detect-tools'

const execFileAsync = promisify(execFile)

let cachedPio: string | null = null

async function getPio(): Promise<string> {
  if (cachedPio) return cachedPio
  const tools = await detectTools()
  if (!tools.platformio) throw new Error('PlatformIO CLI not found')
  cachedPio = tools.platformio
  return cachedPio
}

export async function pioBuild(dir: string, env?: string) {
  const pio = await getPio()
  const args = ['run']
  if (env) args.push('-e', env)
  return execFileAsync(pio, args, { cwd: dir, timeout: 120000 })
}

export async function pioTest(dir: string, env?: string) {
  const pio = await getPio()
  const args = ['test']
  if (env) args.push('-e', env)
  return execFileAsync(pio, args, { cwd: dir, timeout: 120000 })
}

export async function pioUpload(dir: string, env?: string) {
  const pio = await getPio()
  const args = ['run', '-t', 'upload']
  if (env) args.push('-e', env)
  return execFileAsync(pio, args, { cwd: dir, timeout: 120000 })
}
