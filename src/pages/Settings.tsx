import { useState } from 'react'
import { useProjectStore } from '@/stores/project'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Check, X } from 'lucide-react'

export default function Settings() {
  const { toolPaths, detectTools } = useProjectStore()
  const [ghToken, setGhToken] = useState('')
  const [mascaradeUrl, setMascaradeUrl] = useState('http://localhost:8100')

  return (
    <div className="p-6 max-w-2xl space-y-6">
      <h1 className="text-xl font-bold">Settings</h1>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">GitHub Authentication</CardTitle>
          <CardDescription>Personal access token for GitHub API</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex gap-2">
            <Input type="password" placeholder="ghp_..." value={ghToken} onChange={e => setGhToken(e.target.value)} />
            <Button onClick={() => window.electronAPI.invoke('github:init', ghToken)}>Connect</Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Mascarade AI</CardTitle>
          <CardDescription>URL for mascarade-core backend</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2">
            <Input value={mascaradeUrl} onChange={e => setMascaradeUrl(e.target.value)} />
            <Button onClick={() => window.electronAPI.invoke('mascarade:configure', { baseUrl: mascaradeUrl })}>Save</Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Detected Tools</CardTitle>
          <CardDescription>
            <Button variant="link" size="sm" className="p-0 h-auto" onClick={detectTools}>Refresh</Button>
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {toolPaths && Object.entries(toolPaths).map(([k, v]) => (
            <div key={k} className="flex items-center gap-2 text-sm">
              {v ? <Check size={14} className="text-green-400" /> : <X size={14} className="text-red-400" />}
              <span className="font-mono">{k}</span>
              {v && <Badge variant="secondary" className="text-xs font-mono truncate max-w-xs">{v as string}</Badge>}
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}
