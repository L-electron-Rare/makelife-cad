import chokidar, { FSWatcher } from 'chokidar'
import { BrowserWindow } from 'electron'

let watcher: FSWatcher | null = null

export function startWatching(dir: string, mainWindow: BrowserWindow) {
  stopWatching()
  watcher = chokidar.watch([
    '**/*.kicad_sch', '**/*.kicad_pcb', '**/*.kicad_pro',
    '**/*.FCStd', '**/*.step', '**/*.stl',
    '**/*.cpp', '**/*.h', '**/*.c', '**/*.py',
    '**/platformio.ini',
  ], {
    cwd: dir,
    ignoreInitial: true,
    ignored: ['**/node_modules/**', '**/.git/**', '**/build/**', '**/dist/**'],
    persistent: true,
  })

  const notify = (event: string, filePath: string) => {
    mainWindow.webContents.send('watcher:changed', { event, path: filePath })
  }

  watcher.on('add', (p) => notify('add', p))
  watcher.on('change', (p) => notify('change', p))
  watcher.on('unlink', (p) => notify('unlink', p))
}

export function stopWatching() {
  if (watcher) { watcher.close(); watcher = null }
}
