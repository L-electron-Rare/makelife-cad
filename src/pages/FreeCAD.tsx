import { useCallback, useEffect, useMemo, useState } from 'react'
import { useProjectStore } from '@/stores/project'
import type {
  FreeCADDocument,
  FreeCADExportResult,
  FreeCADStatusSummary,
} from '@/lib/types'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { ScrollArea } from '@/components/ui/scroll-area'
import { cn } from '@/lib/utils'
import {
  Cuboid,
  FolderOpen,
  RefreshCw,
  Play,
  FolderSearch,
  Cable,
  HardDrive,
  Box,
} from 'lucide-react'

type FileEntry = {
  name: string
  path: string
  isDirectory: boolean
}

function joinPath(base: string, child: string): string {
  return `${base.replace(/[\\/]$/, '')}/${child.replace(/^[\\/]/, '')}`
}

function relativePath(base: string, fullPath: string): string {
  const normalizedBase = `${base.replace(/\/+$/, '')}/`
  return fullPath.startsWith(normalizedBase)
    ? fullPath.slice(normalizedBase.length)
    : fullPath
}

async function scanFreeCADDocuments(root: string, baseRoot = root): Promise<FreeCADDocument[]> {
  const entries = await window.electronAPI.readDir(root) as FileEntry[]
  const docs: FreeCADDocument[] = []

  for (const entry of entries) {
    if (entry.isDirectory) {
      docs.push(...await scanFreeCADDocuments(entry.path, baseRoot))
      continue
    }

    if (!entry.name.toLowerCase().endsWith('.fcstd')) continue

    docs.push({
      name: entry.name.replace(/\.fcstd$/i, ''),
      path: entry.path,
      relativePath: relativePath(baseRoot, entry.path),
    })
  }

  return docs.sort((a, b) => a.relativePath.localeCompare(b.relativePath))
}

function toneForStatus(status: string): string {
  switch (status) {
    case 'available':
      return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
    case 'incompatible':
      return 'bg-amber-500/10 text-amber-400 border-amber-500/20'
    case 'offline':
      return 'bg-slate-500/10 text-slate-300 border-slate-500/20'
    default:
      return 'bg-rose-500/10 text-rose-400 border-rose-500/20'
  }
}

function hintForStatus(status: string, version: string | null, fallback: string): string {
  if (version) return version
  if (status === 'offline') return 'offline'
  return fallback
}

function isLocalGatewayUrl(url: string | undefined): boolean {
  if (!url) return false
  try {
    const host = new URL(url).hostname.toLowerCase()
    return host === 'localhost' || host === '127.0.0.1' || host === '::1'
  } catch {
    return false
  }
}

export default function FreeCADPage() {
  const { projectPath, config, toolPaths, openProject, detectTools } = useProjectStore()
  const [documents, setDocuments] = useState<FreeCADDocument[]>([])
  const [selectedPath, setSelectedPath] = useState<string | null>(null)
  const [status, setStatus] = useState<FreeCADStatusSummary | null>(null)
  const [lastExport, setLastExport] = useState<FreeCADExportResult | null>(null)
  const [logs, setLogs] = useState<string[]>([])
  const [loadingDocs, setLoadingDocs] = useState(false)
  const [refreshingStatus, setRefreshingStatus] = useState(false)
  const [exportingFormat, setExportingFormat] = useState<'step' | 'stl' | null>(null)

  const mechanicalRoot = useMemo(() => {
    if (!projectPath) return null
    return joinPath(projectPath, config?.paths?.mechanical ?? 'mechanical')
  }, [config?.paths?.mechanical, projectPath])

  const selectedDocument = documents.find((doc) => doc.path === selectedPath) ?? documents[0] ?? null

  const appendLog = useCallback((line: string) => {
    const stamp = new Date().toLocaleTimeString('fr-FR', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
    setLogs((current) => [...current, `[${stamp}] ${line}`])
  }, [])

  const refreshStatus = useCallback(async () => {
    setRefreshingStatus(true)
    try {
      const nextStatus = await window.electronAPI.invoke('tools:freecadStatus') as FreeCADStatusSummary
      setStatus(nextStatus)
    } catch (error) {
      appendLog(`Status refresh failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    } finally {
      setRefreshingStatus(false)
    }
  }, [appendLog])

  const refreshDocuments = useCallback(async () => {
    if (!mechanicalRoot) {
      setDocuments([])
      setSelectedPath(null)
      return
    }

    setLoadingDocs(true)
    try {
      const nextDocuments = await scanFreeCADDocuments(mechanicalRoot)
      setDocuments(nextDocuments)
      setSelectedPath((current) => {
        if (current && nextDocuments.some((doc) => doc.path === current)) return current
        return nextDocuments[0]?.path ?? null
      })
    } catch (error) {
      setDocuments([])
      setSelectedPath(null)
      appendLog(`Document scan failed: ${error instanceof Error ? error.message : 'unknown error'}`)
    } finally {
      setLoadingDocs(false)
    }
  }, [appendLog, mechanicalRoot])

  useEffect(() => {
    void detectTools()
    void refreshStatus()
  }, [detectTools, refreshStatus])

  useEffect(() => {
    void refreshDocuments()
  }, [refreshDocuments])

  const handleOpenProject = async () => {
    const dir = await window.electronAPI.openDirDialog()
    if (dir) {
      await openProject(dir)
    }
  }

  const handleLaunch = async () => {
    if (!selectedDocument) return
    await window.electronAPI.invoke('tools:launchFreecad', selectedDocument.path)
    appendLog(`Opened ${selectedDocument.relativePath} in FreeCAD.`)
  }

  const handleReveal = async (targetPath?: string) => {
    if (!targetPath) return
    await window.electronAPI.invoke('shell:revealInFinder', targetPath)
  }

  const handleExport = async (format: 'step' | 'stl') => {
    if (!selectedDocument || !mechanicalRoot) return

    setExportingFormat(format)
    appendLog(`Export ${format.toUpperCase()} started for ${selectedDocument.relativePath}.`)

    try {
      const result = await window.electronAPI.invoke(
        'tools:freecadExport',
        selectedDocument.path,
        format,
        joinPath(mechanicalRoot, 'exports')
      ) as FreeCADExportResult

      setLastExport(result)

      if (result.ok) {
        appendLog(
          `Export ${format.toUpperCase()} finished via ${result.mode}` +
          (result.fallbackReason ? ` (fallback: ${result.fallbackReason})` : '') +
          (result.outputPath ? ` -> ${result.outputPath}` : '')
        )
      } else {
        appendLog(`Export ${format.toUpperCase()} failed: ${result.error ?? result.stderr ?? 'unknown error'}`)
      }

      await refreshStatus()
    } finally {
      setExportingFormat(null)
    }
  }

  if (!projectPath) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-4">
        <Cuboid size={52} className="text-muted-foreground" />
        <div className="text-center space-y-1">
          <p className="font-medium">Open a YiACAD project to work with FreeCAD files</p>
          <p className="text-sm text-muted-foreground">The page scans `mechanical/` recursively for `.FCStd` documents.</p>
        </div>
        <Button onClick={handleOpenProject}>
          <FolderOpen size={16} className="mr-2" />
          Open Project
        </Button>
      </div>
    )
  }

  return (
    <div className="h-full grid grid-cols-[320px,1fr]">
      <aside className="border-r bg-secondary/30">
        <div className="p-4 space-y-4">
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Cuboid size={16} />
                FreeCAD Runtime
              </CardTitle>
              <CardDescription>Target runtime: {status?.local.version === '1.1.0' ? '1.1.0' : '1.1.x'}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-3 text-sm">
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-muted-foreground flex items-center gap-2"><HardDrive size={14} /> Local</span>
                  <Badge className={cn('border', toneForStatus(status?.local.status ?? 'unavailable'))}>
                    {status?.local.status ?? 'checking'}
                  </Badge>
                </div>
                <p className="font-mono text-xs text-muted-foreground break-all">
                  {hintForStatus(status?.local.status ?? 'unavailable', status?.local.version ?? null, toolPaths?.freecadCmd ?? 'missing')}
                </p>
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-muted-foreground flex items-center gap-2"><Cable size={14} /> Gateway</span>
                  <Badge className={cn('border', toneForStatus(status?.gateway?.status ?? 'unavailable'))}>
                    {status?.gateway?.status ?? 'disabled'}
                  </Badge>
                </div>
                <p className="font-mono text-xs text-muted-foreground break-all">
                  {status?.gatewayUrl ?? 'http://localhost:8001'}
                </p>
              </div>

              <div className="rounded-md border border-border/60 px-3 py-2 bg-background/60">
                <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Chosen mode</p>
                <p className="font-medium">{status?.chosenMode ?? 'checking'}</p>
                {status?.gatewayUrl && !isLocalGatewayUrl(status.gatewayUrl) && (
                  <p className="mt-1 text-xs text-muted-foreground">
                    Remote gateway configured: FreeCAD keeps exports local by design.
                  </p>
                )}
              </div>

              <Button variant="outline" className="w-full" onClick={() => { void refreshStatus(); void detectTools() }}>
                <RefreshCw size={14} className={cn('mr-2', refreshingStatus && 'animate-spin')} />
                Refresh runtime
              </Button>
            </CardContent>
          </Card>

          <Card className="min-h-0">
            <CardHeader className="pb-3">
              <CardTitle className="text-base flex items-center gap-2">
                <Box size={16} />
                Mechanical Docs
              </CardTitle>
              <CardDescription>
                {loadingDocs ? 'Scanning mechanical/' : `${documents.length} .FCStd file${documents.length > 1 ? 's' : ''}`}
              </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              <ScrollArea className="h-[calc(100vh-24rem)] px-3 pb-3">
                <div className="space-y-1">
                  {documents.length === 0 ? (
                    <div className="px-3 py-6 text-sm text-muted-foreground">
                      No FreeCAD documents found under <span className="font-mono">mechanical/</span>.
                    </div>
                  ) : (
                    documents.map((doc) => (
                      <button
                        key={doc.path}
                        onClick={() => setSelectedPath(doc.path)}
                        className={cn(
                          'w-full rounded-lg border px-3 py-2 text-left transition-colors',
                          selectedDocument?.path === doc.path
                            ? 'border-accent bg-accent/10'
                            : 'border-transparent hover:border-border hover:bg-background/60'
                        )}
                      >
                        <div className="font-medium truncate">{doc.name}</div>
                        <div className="text-xs text-muted-foreground font-mono break-all">{doc.relativePath}</div>
                      </button>
                    ))
                  )}
                </div>
              </ScrollArea>
            </CardContent>
          </Card>
        </div>
      </aside>

      <main className="p-6 space-y-6 overflow-auto">
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">
              {selectedDocument ? selectedDocument.name : 'Select a FreeCAD document'}
            </CardTitle>
            <CardDescription className="font-mono">
              {selectedDocument?.path ?? mechanicalRoot}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex flex-wrap gap-2">
              <Button onClick={handleLaunch} disabled={!selectedDocument}>
                <Play size={16} className="mr-2" />
                Open in FreeCAD
              </Button>
              <Button variant="outline" onClick={() => void handleReveal(selectedDocument?.path)} disabled={!selectedDocument}>
                <FolderSearch size={16} className="mr-2" />
                Reveal
              </Button>
              <Button
                variant="outline"
                onClick={() => { void handleExport('step') }}
                disabled={!selectedDocument || exportingFormat !== null}
              >
                STEP
              </Button>
              <Button
                variant="outline"
                onClick={() => { void handleExport('stl') }}
                disabled={!selectedDocument || exportingFormat !== null}
              >
                STL
              </Button>
              <Button variant="ghost" onClick={() => { void refreshDocuments() }}>
                <RefreshCw size={16} className={cn('mr-2', loadingDocs && 'animate-spin')} />
                Rescan
              </Button>
            </div>

            {status?.local.compatible === false && (
              <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-200">
                FreeCAD {status.local.version ?? 'unknown'} is not the expected local runtime. YiACAD targets 1.1.0 and accepts 1.1.x.
              </div>
            )}

            {lastExport && (
              <div className="rounded-lg border border-border/70 bg-background/70 p-4 space-y-2">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="text-sm font-medium">Last export</p>
                    <p className="text-xs text-muted-foreground">
                      Mode: <span className="font-mono">{lastExport.mode}</span>
                      {lastExport.versionUsed ? ` · FreeCAD ${lastExport.versionUsed}` : ''}
                    </p>
                  </div>
                  <Badge className={cn('border', lastExport.ok
                    ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                    : 'bg-rose-500/10 text-rose-400 border-rose-500/20'
                  )}>
                    {lastExport.ok ? 'success' : 'failed'}
                  </Badge>
                </div>

                {lastExport.outputPath && (
                  <button
                    className="text-left text-xs font-mono text-muted-foreground hover:text-foreground"
                    onClick={() => void handleReveal(lastExport.outputPath)}
                  >
                    {lastExport.outputPath}
                  </button>
                )}

                {lastExport.fallbackReason && (
                  <p className="text-xs text-amber-300">
                    Gateway fallback: {lastExport.fallbackReason}
                  </p>
                )}

                {(lastExport.error || lastExport.stderr) && (
                  <pre className="rounded bg-secondary/60 p-3 text-xs whitespace-pre-wrap break-words">
                    {lastExport.error ?? lastExport.stderr}
                  </pre>
                )}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Activity log</CardTitle>
            <CardDescription>Launches, exports, fallback decisions and scan errors appear here.</CardDescription>
          </CardHeader>
          <CardContent>
            <ScrollArea className="h-64 rounded-md border border-border/70 bg-background/70">
              <div className="p-4 space-y-2 text-sm">
                {logs.length === 0 ? (
                  <p className="text-muted-foreground">No FreeCAD activity yet.</p>
                ) : (
                  logs.map((line, index) => (
                    <div key={`${line}-${index}`} className="font-mono text-xs text-muted-foreground">
                      {line}
                    </div>
                  ))
                )}
              </div>
            </ScrollArea>
          </CardContent>
        </Card>
      </main>
    </div>
  )
}
