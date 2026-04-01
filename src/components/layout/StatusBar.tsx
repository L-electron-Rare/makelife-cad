import { useProjectStore } from '@/stores/project'

export function StatusBar() {
  const projectName = useProjectStore((s) => s.projectName)

  return (
    <div className="h-6 flex items-center px-3 bg-secondary/50 border-t text-xs text-muted-foreground">
      <span>{projectName ?? 'No project open'}</span>
      <span className="ml-auto">MakeLife Desktop v0.1.0</span>
    </div>
  )
}
