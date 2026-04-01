import { spawn, ChildProcess } from 'child_process'
import { EventEmitter } from 'events'

interface ManagedProcess {
  id: string
  process: ChildProcess
  label: string
}

class ProcessManager extends EventEmitter {
  private processes = new Map<string, ManagedProcess>()

  launch(id: string, command: string, args: string[], label: string) {
    if (this.processes.has(id)) this.kill(id)
    const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'], detached: false })
    child.stdout?.on('data', (d) => this.emit('stdout', id, d.toString()))
    child.stderr?.on('data', (d) => this.emit('stderr', id, d.toString()))
    child.on('exit', (code) => { this.processes.delete(id); this.emit('exit', id, code) })
    this.processes.set(id, { id, process: child, label })
  }

  kill(id: string) {
    const m = this.processes.get(id)
    if (m) { m.process.kill(); this.processes.delete(id) }
  }

  killAll() { for (const [id] of this.processes) this.kill(id) }
}

export const processManager = new ProcessManager()
