import { useState, useEffect } from 'react'
import { ChevronRight, ChevronDown, File, Folder } from 'lucide-react'

function getFileIcon(name: string): string | null {
  if (name.endsWith('.kicad_sch')) return '📐'
  if (name.endsWith('.kicad_pcb')) return '🔲'
  if (name.endsWith('.kicad_pro')) return '📦'
  if (name.endsWith('.FCStd')) return '🧊'
  if (name.endsWith('.step') || name.endsWith('.stl')) return '🧊'
  if (name.endsWith('.cpp') || name.endsWith('.h') || name.endsWith('.c')) return '⚡'
  if (name === 'platformio.ini') return '🔧'
  return null
}

interface FileEntry {
  name: string
  path: string
  isDirectory: boolean
}

interface FileTreeProps {
  rootPath: string
  onFileSelect: (path: string) => void
  onFileOpen: (path: string) => void
}

export function FileTree({ rootPath, onFileSelect, onFileOpen }: FileTreeProps) {
  const [entries, setEntries] = useState<FileEntry[]>([])

  useEffect(() => {
    window.electronAPI.readDir(rootPath).then(setEntries)
  }, [rootPath])

  return (
    <div className="text-sm">
      {entries.map(entry => (
        <TreeNode key={entry.path} entry={entry} depth={0} onFileSelect={onFileSelect} onFileOpen={onFileOpen} />
      ))}
    </div>
  )
}

function TreeNode({ entry, depth, onFileSelect, onFileOpen }: {
  entry: FileEntry; depth: number; onFileSelect: (p: string) => void; onFileOpen: (p: string) => void
}) {
  const [expanded, setExpanded] = useState(false)
  const [children, setChildren] = useState<FileEntry[]>([])
  const icon = getFileIcon(entry.name)

  const handleClick = () => {
    if (entry.isDirectory) {
      if (!expanded) window.electronAPI.readDir(entry.path).then(setChildren)
      setExpanded(!expanded)
    } else {
      onFileSelect(entry.path)
    }
  }

  return (
    <>
      <div className="flex items-center gap-1 py-0.5 px-2 cursor-pointer hover:bg-accent/50 rounded-sm"
           style={{ paddingLeft: `${depth * 16 + 8}px` }}
           onClick={handleClick}
           onDoubleClick={() => !entry.isDirectory && onFileOpen(entry.path)}>
        {entry.isDirectory ? (expanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />) : <span className="w-3.5" />}
        {icon ? <span className="text-xs">{icon}</span> : entry.isDirectory ? <Folder size={14} className="text-blue-400" /> : <File size={14} className="text-muted-foreground" />}
        <span className="truncate">{entry.name}</span>
      </div>
      {expanded && children.map(child => (
        <TreeNode key={child.path} entry={child} depth={depth + 1} onFileSelect={onFileSelect} onFileOpen={onFileOpen} />
      ))}
    </>
  )
}
