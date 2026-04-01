import { FileTree } from '@/components/file-tree/FileTree'
import { useProjectStore } from '@/stores/project'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { FolderOpen } from 'lucide-react'

export default function Explorer() {
  const { projectPath } = useProjectStore()
  const [selectedFile, setSelectedFile] = useState<string | null>(null)

  const handleFileOpen = async (filePath: string) => {
    if (filePath.match(/\.kicad_(sch|pcb|pro)$/)) {
      await window.electronAPI.invoke('tools:launchKicad', filePath)
    } else if (filePath.match(/\.(FCStd|step|stl)$/)) {
      await window.electronAPI.invoke('tools:launchFreecad', filePath)
    }
  }

  if (!projectPath) {
    return (
      <div className="flex flex-col items-center justify-center h-full gap-4">
        <FolderOpen size={48} className="text-muted-foreground" />
        <p className="text-muted-foreground">Open a project to browse files</p>
        <Button onClick={async () => {
          const dir = await window.electronAPI.openDirDialog()
          if (dir) useProjectStore.getState().openProject(dir)
        }}>Open Project</Button>
      </div>
    )
  }

  return (
    <div className="flex h-full">
      <div className="w-72 border-r overflow-auto">
        <FileTree rootPath={projectPath} onFileSelect={setSelectedFile} onFileOpen={handleFileOpen} />
      </div>
      <div className="flex-1 p-4">
        {selectedFile ? (
          <div className="text-sm text-muted-foreground">
            <p className="font-mono">{selectedFile}</p>
            <p className="mt-2">Double-click to open in native editor</p>
          </div>
        ) : (
          <p className="text-muted-foreground">Select a file</p>
        )}
      </div>
    </div>
  )
}
