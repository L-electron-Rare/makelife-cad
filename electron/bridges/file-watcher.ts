import type { BrowserWindow } from 'electron'
import { watch, type FSWatcher } from 'fs'
import path from 'path'

let watcher: FSWatcher | null = null

export function startWatching(dir: string, window: BrowserWindow): void {
  stopWatching()

  watcher = watch(dir, { recursive: true }, (_eventType, filename) => {
    window.webContents.send('watcher:changed', {
      path: filename ? path.join(dir, filename.toString()) : dir,
    })
  })
}

export function stopWatching(): void {
  watcher?.close()
  watcher = null
}
