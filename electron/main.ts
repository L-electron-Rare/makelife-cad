import { app, BrowserWindow, ipcMain, dialog } from 'electron'
import path from 'path'
import { readdir, readFile, writeFile, mkdir } from 'fs/promises'
import { detectTools } from './utils/detect-tools'

let mainWindow: BrowserWindow | null = null

// Tool detection
ipcMain.handle('tools:detect', () => detectTools())

// File system
ipcMain.handle('fs:readDir', async (_, dirPath: string) => {
  const entries = await readdir(dirPath, { withFileTypes: true })
  return entries
    .filter(e => !e.name.startsWith('.'))
    .map(e => ({ name: e.name, isDirectory: e.isDirectory(), path: path.join(dirPath, e.name) }))
})

ipcMain.handle('fs:readFile', async (_, filePath: string) => readFile(filePath, 'utf-8'))

ipcMain.handle('dialog:openDir', async () => {
  const result = await dialog.showOpenDialog(mainWindow!, { properties: ['openDirectory'] })
  return result.canceled ? null : result.filePaths[0]
})

// Project config
ipcMain.handle('project:getConfig', async (_, projectPath: string) => {
  try {
    const raw = await readFile(path.join(projectPath, '.makelife', 'config.json'), 'utf-8')
    return JSON.parse(raw)
  } catch { return null }
})

ipcMain.handle('project:create', async (_, name: string, projectPath: string) => {
  for (const dir of ['hardware', 'mechanical', 'firmware', 'docs', '.makelife']) {
    await mkdir(path.join(projectPath, dir), { recursive: true })
  }
  const config = { name, version: '0.1.0', paths: { hardware: 'hardware', mechanical: 'mechanical', firmware: 'firmware', docs: 'docs' }, tools: {}, remotes: {} }
  await writeFile(path.join(projectPath, '.makelife', 'config.json'), JSON.stringify(config, null, 2))
})

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 1024,
    minHeight: 600,
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL)
    mainWindow.webContents.openDevTools()
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'))
  }
}

app.whenReady().then(createWindow)
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})
