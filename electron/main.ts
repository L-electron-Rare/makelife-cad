import { app, BrowserWindow, ipcMain, dialog } from 'electron'
import path from 'path'
import { readdir, readFile, writeFile, mkdir } from 'fs/promises'
import { detectTools } from './utils/detect-tools'
import * as kicadBridge from './bridges/kicad'
import * as mascaradeBridge from './bridges/mascarade'
import { launchFreecad } from './bridges/freecad'
import { processManager } from './utils/process-manager'
import { startWatching, stopWatching } from './bridges/file-watcher'
import * as gitBridge from './bridges/git'
import * as githubBridge from './bridges/github'
import * as pioBridge from './bridges/platformio'

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

// Tool launchers
ipcMain.handle('tools:launchKicad', async (_, filePath: string) => kicadBridge.launchKicad(filePath))
ipcMain.handle('tools:launchFreecad', async (_, filePath: string) => launchFreecad(filePath))

// File watcher
ipcMain.handle('watcher:start', async (_, dir: string) => {
  if (mainWindow) startWatching(dir, mainWindow)
})
ipcMain.handle('watcher:stop', async () => stopWatching())

// Git bridge
ipcMain.handle('git:status', (_, dir) => gitBridge.gitStatus(dir))
ipcMain.handle('git:log', (_, dir, depth) => gitBridge.gitLog(dir, depth))
ipcMain.handle('git:add', (_, dir, filepath) => gitBridge.gitAdd(dir, filepath))
ipcMain.handle('git:commit', (_, dir, message, author) => gitBridge.gitCommit(dir, message, author))
ipcMain.handle('git:branches', (_, dir) => gitBridge.gitBranches(dir))
ipcMain.handle('git:currentBranch', (_, dir) => gitBridge.gitCurrentBranch(dir))

// GitHub bridge
ipcMain.handle('github:init', (_, token) => githubBridge.initGitHub(token))
ipcMain.handle('github:issues', (_, owner, repo, state) => githubBridge.listIssues(owner, repo, state))
ipcMain.handle('github:createIssue', (_, owner, repo, title, body) => githubBridge.createIssue(owner, repo, title, body))
ipcMain.handle('github:updateIssue', (_, owner, repo, num, update) => githubBridge.updateIssue(owner, repo, num, update))
ipcMain.handle('github:prs', (_, owner, repo, state) => githubBridge.listPRs(owner, repo, state))
ipcMain.handle('github:workflowRuns', (_, owner, repo) => githubBridge.listWorkflowRuns(owner, repo))

// PlatformIO bridge
ipcMain.handle('pio:build', (_, dir, env) => pioBridge.pioBuild(dir, env))
ipcMain.handle('pio:test', (_, dir, env) => pioBridge.pioTest(dir, env))
ipcMain.handle('pio:upload', (_, dir, env) => pioBridge.pioUpload(dir, env))

// KiCad CLI bridge
ipcMain.handle('kicad:erc', (_, schPath, outputDir) => kicadBridge.runErc(schPath, outputDir))
ipcMain.handle('kicad:drc', (_, pcbPath, outputDir) => kicadBridge.runDrc(pcbPath, outputDir))
ipcMain.handle('kicad:exportSvg', (_, schPath, outputDir) => kicadBridge.exportSchematicSvg(schPath, outputDir))
ipcMain.handle('kicad:exportGerbers', (_, pcbPath, outputDir) => kicadBridge.exportGerbers(pcbPath, outputDir))
ipcMain.handle('kicad:exportBom', (_, schPath, outputPath) => kicadBridge.exportBom(schPath, outputPath))

// Mascarade AI bridge
ipcMain.handle('mascarade:health', () => mascaradeBridge.healthCheck())
ipcMain.handle('mascarade:chat', (_, messages) => mascaradeBridge.chatSync(messages))
ipcMain.handle('mascarade:configure', (_, cfg) => mascaradeBridge.configureMascarade(cfg))

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

app.on('before-quit', () => {
  stopWatching()
  processManager.killAll()
})

app.whenReady().then(createWindow)
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow()
})
