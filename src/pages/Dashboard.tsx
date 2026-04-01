import { useProjectStore } from '@/stores/project'
import { useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { FolderOpen, Plus, Check, X } from 'lucide-react'

export default function Dashboard() {
  const { projectPath, config, toolPaths, detectTools, openProject } = useProjectStore()

  useEffect(() => { detectTools() }, [])

  if (!projectPath) {
    return (
      <div className="p-8 max-w-2xl mx-auto space-y-8">
        <div>
          <h1 className="text-2xl font-bold">MakeLife Desktop</h1>
          <p className="text-muted-foreground mt-1">Open-source hardware engineering platform</p>
        </div>

        <div className="flex gap-3">
          <Button onClick={async () => {
            const dir = await window.electronAPI.openDirDialog()
            if (dir) openProject(dir)
          }}>
            <FolderOpen size={16} className="mr-2" /> Open Project
          </Button>
          <Button variant="outline"><Plus size={16} className="mr-2" /> New Project</Button>
        </div>

        {toolPaths && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Tool Detection</CardTitle>
              <CardDescription>External tools found on this system</CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              {Object.entries(toolPaths).map(([key, val]) => (
                <div key={key} className="flex items-center gap-2 text-sm">
                  {val ? <Check size={14} className="text-green-400" /> : <X size={14} className="text-red-400" />}
                  <span className="font-mono">{key}</span>
                  {val && <Badge variant="secondary" className="text-xs font-mono truncate max-w-xs">{val as string}</Badge>}
                </div>
              ))}
            </CardContent>
          </Card>
        )}
      </div>
    )
  }

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold">{config?.name ?? 'Project'}</h1>
        <p className="text-sm text-muted-foreground font-mono">{projectPath}</p>
      </div>
      <div className="grid grid-cols-3 gap-4">
        <Card>
          <CardHeader><CardTitle className="text-sm">Hardware</CardTitle></CardHeader>
          <CardContent><p className="text-muted-foreground text-sm">{config?.paths?.hardware ?? 'Not configured'}</p></CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Mechanical</CardTitle></CardHeader>
          <CardContent><p className="text-muted-foreground text-sm">{config?.paths?.mechanical ?? 'Not configured'}</p></CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Firmware</CardTitle></CardHeader>
          <CardContent><p className="text-muted-foreground text-sm">{config?.paths?.firmware ?? 'Not configured'}</p></CardContent>
        </Card>
      </div>
    </div>
  )
}
