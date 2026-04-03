import { useEffect } from 'react'
import { cn } from '@/lib/utils'
import { useProjectStore } from '@/stores/project'

function tailPath(pathname: string | null): string | null {
  if (!pathname) return null
  const parts = pathname.split(/[\\/]/).filter(Boolean)
  return parts[parts.length - 1] ?? pathname
}

export function StatusBar() {
  const config = useProjectStore((s) => s.config)
  const projectPath = useProjectStore((s) => s.projectPath)
  const toolPaths = useProjectStore((s) => s.toolPaths)
  const appSettings = useProjectStore((s) => s.appSettings)
  const gatewayStatus = useProjectStore((s) => s.gatewayStatus)
  const loadAppSettings = useProjectStore((s) => s.loadAppSettings)
  const refreshGatewayStatus = useProjectStore((s) => s.refreshGatewayStatus)

  const projectLabel = config?.name ?? tailPath(projectPath) ?? 'No project open'
  const freecadReady = Boolean(toolPaths?.freecadCmd)

  useEffect(() => {
    void loadAppSettings()
  }, [loadAppSettings])

  useEffect(() => {
    if (appSettings?.gatewayUrl) {
      void refreshGatewayStatus()
    }
  }, [appSettings?.gatewayUrl, refreshGatewayStatus])

  const gatewayTone = gatewayStatus?.state === 'local'
    ? 'bg-emerald-500/10 text-emerald-400'
    : gatewayStatus?.state === 'remote'
      ? 'bg-sky-500/10 text-sky-400'
      : 'bg-rose-500/10 text-rose-400'

  return (
    <div className="h-6 flex items-center gap-3 px-3 bg-secondary/50 border-t text-xs text-muted-foreground">
      <span>{projectLabel}</span>
      <span
        className={cn(
          'inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium',
          freecadReady
            ? 'bg-emerald-500/10 text-emerald-400'
            : 'bg-rose-500/10 text-rose-400'
        )}
      >
        FreeCAD {freecadReady ? 'ready' : 'missing'}
      </span>
      <span
        className={cn(
          'inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-medium uppercase',
          gatewayTone
        )}
        title={gatewayStatus?.error ?? appSettings?.gatewayUrl}
      >
        Gateway {gatewayStatus?.state ?? '...'}
      </span>
      <span className="max-w-[24rem] truncate font-mono text-[10px]" title={appSettings?.gatewayUrl}>
        Gateway {appSettings?.gatewayUrl ?? 'loading...'}
      </span>
      <span className="ml-auto">MakeLife Desktop v0.1.0</span>
    </div>
  )
}
