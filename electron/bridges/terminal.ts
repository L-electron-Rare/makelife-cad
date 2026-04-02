import * as pty from 'node-pty'
import { ipcMain, BrowserWindow } from 'electron'
import path from 'path'
import os from 'os'

export interface ShellSession {
  id: string
  process: pty.IPty
  preset: 'shell' | 'platformio' | 'ngspice' | 'cmake'
}

const sessions = new Map<string, ShellSession>()

function getPresetConfig(preset: ShellSession['preset'], cwd?: string): {
  shell: string
  args: string[]
  env: NodeJS.ProcessEnv
  cwd: string
} {
  const base = process.env.SHELL ?? '/bin/zsh'
  const home = os.homedir()

  switch (preset) {
    case 'platformio':
      return {
        shell: base,
        args: [],
        env: {
          ...process.env,
          PATH: `${home}/.platformio/penv/bin:${process.env.PATH}`,
        },
        cwd: cwd ?? path.join(home, 'Documents/Projets/Factory 4 Life/makelife-firmware'),
      }
    case 'ngspice':
      return {
        shell: 'ngspice',
        args: ['-i'],
        env: { ...process.env },
        cwd: cwd ?? path.join(home, 'Documents/Projets/Factory 4 Life/spice-life/circuits'),
      }
    case 'cmake':
      return {
        shell: base,
        args: [],
        env: { ...process.env },
        cwd: cwd ?? path.join(home, 'Documents/Projets/Factory 4 Life/makelife-firmware/build'),
      }
    case 'shell':
    default:
      return {
        shell: base,
        args: [],
        env: { ...process.env },
        cwd: cwd ?? home,
      }
  }
}

export function spawn(
  preset: ShellSession['preset'],
  cwd: string | undefined,
  win: BrowserWindow
): string {
  const id = `${preset}-${Date.now()}`
  const cfg = getPresetConfig(preset, cwd)

  const proc = pty.spawn(cfg.shell, cfg.args, {
    name: 'xterm-256color',
    cols: 80,
    rows: 24,
    cwd: cfg.cwd,
    env: cfg.env as Record<string, string>,
  })

  proc.onData((data) => {
    win.webContents.send(`terminal:data:${id}`, data)
  })

  proc.onExit(() => {
    win.webContents.send(`terminal:exit:${id}`)
    sessions.delete(id)
  })

  sessions.set(id, { id, process: proc, preset })
  return id
}

export function write(id: string, data: string): void {
  sessions.get(id)?.process.write(data)
}

export function resize(id: string, cols: number, rows: number): void {
  sessions.get(id)?.process.resize(cols, rows)
}

export function kill(id: string): void {
  const session = sessions.get(id)
  if (session) {
    session.process.kill()
    sessions.delete(id)
  }
}

export function killAll(): void {
  for (const [id] of sessions) {
    kill(id)
  }
}

export function registerTerminalHandlers(win: BrowserWindow): void {
  ipcMain.handle('terminal:spawn', (_event, preset: ShellSession['preset'], cwd?: string) => {
    return spawn(preset, cwd, win)
  })

  ipcMain.handle('terminal:write', (_event, id: string, data: string) => {
    write(id, data)
  })

  ipcMain.handle('terminal:resize', (_event, id: string, cols: number, rows: number) => {
    resize(id, cols, rows)
  })

  ipcMain.handle('terminal:kill', (_event, id: string) => {
    kill(id)
  })
}
