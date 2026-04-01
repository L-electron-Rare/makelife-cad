import { useEffect, useState } from 'react'
import { useProjectStore } from '@/stores/project'
import { useGitStore } from '@/stores/git'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { ScrollArea } from '@/components/ui/scroll-area'
import { GitBranch, Plus, Check, RefreshCw } from 'lucide-react'

export default function Git() {
  const projectPath = useProjectStore(s => s.projectPath)
  const { currentBranch, status, log, isLoading, refresh, stageFile, commit } = useGitStore()
  const [commitMsg, setCommitMsg] = useState('')

  useEffect(() => { if (projectPath) refresh(projectPath) }, [projectPath])

  if (!projectPath) return <div className="p-8 text-muted-foreground">Open a project first</div>

  const handleCommit = async () => {
    if (!commitMsg.trim()) return
    await commit(projectPath, commitMsg)
    setCommitMsg('')
  }

  return (
    <div className="p-6 space-y-6 max-w-4xl">
      <div className="flex items-center gap-3">
        <GitBranch size={18} />
        <Badge variant="secondary" className="text-sm">{currentBranch ?? '...'}</Badge>
        <Button variant="outline" size="sm" onClick={() => refresh(projectPath)}>
          <RefreshCw size={14} className="mr-1" /> Refresh
        </Button>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-sm">Changes</CardTitle></CardHeader>
        <CardContent>
          {status.length === 0 ? (
            <p className="text-muted-foreground text-sm">Working tree clean</p>
          ) : (
            <div className="space-y-1">
              {status.map(({ filepath, status: st }) => (
                <div key={filepath} className="flex items-center gap-2 text-sm">
                  <Badge variant={st === 'new' ? 'default' : 'secondary'} className="text-xs w-20 justify-center">{st}</Badge>
                  <span className="font-mono flex-1 truncate">{filepath}</span>
                  <Button variant="ghost" size="sm" onClick={() => stageFile(projectPath, filepath)}>
                    <Plus size={14} />
                  </Button>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <div className="flex gap-2">
        <Input placeholder="Commit message..." value={commitMsg} onChange={e => setCommitMsg(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && handleCommit()} />
        <Button onClick={handleCommit} disabled={!commitMsg.trim()}>
          <Check size={14} className="mr-1" /> Commit
        </Button>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-sm">History</CardTitle></CardHeader>
        <CardContent>
          <ScrollArea className="h-64">
            {log.map(entry => (
              <div key={entry.oid} className="py-2 border-b last:border-0">
                <p className="text-sm">{entry.message.split('\n')[0]}</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  {entry.oid.slice(0, 7)} — {entry.author.name} — {new Date(entry.author.timestamp * 1000).toLocaleDateString()}
                </p>
              </div>
            ))}
          </ScrollArea>
        </CardContent>
      </Card>
    </div>
  )
}
