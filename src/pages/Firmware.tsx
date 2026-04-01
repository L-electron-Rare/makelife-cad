import { useState } from 'react'
import Editor from '@monaco-editor/react'
import { useProjectStore } from '@/stores/project'
import { FileTree } from '@/components/file-tree/FileTree'
import { Terminal } from '@/components/terminal/Terminal'
import { Button } from '@/components/ui/button'
import { Play, TestTube, Upload } from 'lucide-react'

export default function Firmware() {
  const projectPath = useProjectStore(s => s.projectPath)
  const config = useProjectStore(s => s.config)
  const [activeFile, setActiveFile] = useState<string | null>(null)
  const [fileContent, setFileContent] = useState('')
  const [buildOutput, setBuildOutput] = useState('')
  const [isBuilding, setIsBuilding] = useState(false)

  const fwDir = projectPath && config?.paths?.firmware ? `${projectPath}/${config.paths.firmware}` : null

  const handleFileSelect = async (path: string) => {
    if (path.match(/\.(c|cpp|h|hpp|py|ini|json|txt|md|yaml|yml)$/)) {
      setActiveFile(path)
      const content = await window.electronAPI.readFile(path)
      setFileContent(content)
    }
  }

  const run = async (action: string) => {
    if (!fwDir) return
    setIsBuilding(true)
    setBuildOutput(`Running ${action}...\n`)
    try {
      const result = await window.electronAPI.invoke(`pio:${action}`, fwDir)
      setBuildOutput(result.stdout + (result.stderr || ''))
    } catch (err: any) {
      setBuildOutput(`Failed: ${err.message}`)
    }
    setIsBuilding(false)
  }

  if (!fwDir) return <div className="p-8 text-muted-foreground">No firmware directory configured</div>

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center gap-2 p-2 border-b">
        <Button size="sm" onClick={() => run('build')} disabled={isBuilding}><Play size={14} className="mr-1" /> Build</Button>
        <Button size="sm" variant="outline" onClick={() => run('test')} disabled={isBuilding}><TestTube size={14} className="mr-1" /> Test</Button>
        <Button size="sm" variant="outline" onClick={() => run('upload')} disabled={isBuilding}><Upload size={14} className="mr-1" /> Flash</Button>
      </div>
      <div className="flex flex-1 overflow-hidden">
        <div className="w-56 border-r overflow-auto">
          <FileTree rootPath={fwDir} onFileSelect={handleFileSelect} onFileOpen={handleFileSelect} />
        </div>
        <div className="flex-1 flex flex-col">
          <div className="flex-1">
            {activeFile ? (
              <Editor height="100%" language={activeFile.endsWith('.py') ? 'python' : 'cpp'}
                value={fileContent} theme="vs-dark"
                options={{ fontSize: 14, minimap: { enabled: false }, bracketPairColorization: { enabled: true } }}
                onChange={v => setFileContent(v ?? '')} />
            ) : (
              <div className="flex items-center justify-center h-full text-muted-foreground">Select a file to edit</div>
            )}
          </div>
          <div className="h-48 border-t"><Terminal output={buildOutput} /></div>
        </div>
      </div>
    </div>
  )
}
