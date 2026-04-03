import { cn } from '@/lib/utils'
import { useUIStore } from '@/stores/ui'
import {
  LayoutDashboard, FolderTree, GitBranch, Play, Bot,
  Cpu, Settings, ChevronLeft, Cuboid
} from 'lucide-react'
import { useProjectStore } from '@/stores/project'

const NAV_ITEMS = [
  { id: 'dashboard' as const, icon: LayoutDashboard, label: 'Dashboard' },
  { id: 'explorer' as const, icon: FolderTree, label: 'Explorer' },
  { id: 'freecad' as const, icon: Cuboid, label: 'FreeCAD' },
  { id: 'git' as const, icon: GitBranch, label: 'Git' },
  { id: 'ci' as const, icon: Play, label: 'CI/CD' },
  { id: 'ai' as const, icon: Bot, label: 'AI' },
  { id: 'firmware' as const, icon: Cpu, label: 'Firmware' },
  { id: 'settings' as const, icon: Settings, label: 'Settings' },
]

export function Sidebar() {
  const { activePage, setActivePage, sidebarCollapsed, toggleSidebar } = useUIStore()
  const toolPaths = useProjectStore((s) => s.toolPaths)

  return (
    <aside className={cn(
      'h-full border-r bg-secondary/50 flex flex-col transition-all',
      sidebarCollapsed ? 'w-14' : 'w-52'
    )}>
      <nav className="flex-1 py-2 space-y-1">
        {NAV_ITEMS.map(({ id, icon: Icon, label }) => (
          <button
            key={id}
            onClick={() => setActivePage(id)}
            className={cn(
              'w-full flex items-center gap-3 px-4 py-2 text-sm transition-colors',
              activePage === id
                ? 'bg-accent text-accent-foreground'
                : 'text-muted-foreground hover:text-foreground hover:bg-accent/50'
            )}
          >
            <Icon size={18} />
            {!sidebarCollapsed && (
              <>
                <span>{label}</span>
                {id === 'freecad' && (
                  <span
                    className={cn(
                      'ml-auto h-2 w-2 rounded-full',
                      toolPaths?.freecadCmd ? 'bg-emerald-400' : 'bg-rose-400'
                    )}
                    title={toolPaths?.freecadCmd ? 'FreeCAD CLI available' : 'FreeCAD CLI missing'}
                  />
                )}
              </>
            )}
          </button>
        ))}
      </nav>
      <button onClick={toggleSidebar} className="p-3 text-muted-foreground hover:text-foreground">
        <ChevronLeft size={18} className={cn('transition-transform', sidebarCollapsed && 'rotate-180')} />
      </button>
    </aside>
  )
}
