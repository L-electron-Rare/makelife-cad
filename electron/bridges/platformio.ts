import { spawn } from 'child_process'
import { processManager } from '../utils/process-manager'

function run(dir: string, args: string[]) {
  return new Promise<{ ok: boolean; stdout?: string; stderr?: string }>((resolve) => {
    const child = spawn('pio', args, { cwd: dir, stdio: ['ignore', 'pipe', 'pipe'] })
    processManager.register(child)
    let stdout = ''
    let stderr = ''
    child.stdout?.on('data', (d) => { stdout += d.toString() })
    child.stderr?.on('data', (d) => { stderr += d.toString() })
    child.on('error', (err) => resolve({ ok: false, stderr: err.message }))
    child.on('exit', (code) => resolve({ ok: code === 0, stdout, stderr }))
  })
}

export function pioBuild(dir: string, env?: string) {
  const args = ['run']
  if (env) args.push('-e', env)
  return run(dir, args)
}

export function pioTest(dir: string, env?: string) {
  const args = ['test']
  if (env) args.push('-e', env)
  return run(dir, args)
}

export function pioUpload(dir: string, env?: string) {
  const args = ['run', '--target', 'upload']
  if (env) args.push('-e', env)
  return run(dir, args)
}
