import type { ChildProcess } from 'child_process'

class ProcessManager {
  private processes = new Set<ChildProcess>()

  register(proc: ChildProcess) {
    this.processes.add(proc)
    proc.on('exit', () => this.processes.delete(proc))
    proc.on('error', () => this.processes.delete(proc))
  }

  killAll() {
    for (const proc of Array.from(this.processes)) {
      try {
        proc.kill('SIGTERM')
      } catch {
        /* ignore */
      }
    }
    this.processes.clear()
  }
}

export const processManager = new ProcessManager()
