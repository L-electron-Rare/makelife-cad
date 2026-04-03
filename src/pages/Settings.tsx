import { useEffect, useMemo, useState } from 'react'
import { useProjectStore } from '@/stores/project'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Check, X } from 'lucide-react'

export default function Settings() {
  const { toolPaths, appSettings, detectTools, loadAppSettings, updateAppSettings } = useProjectStore()
  const [ghToken, setGhToken] = useState('')
  const [gatewayUrl, setGatewayUrl] = useState('http://localhost:8001')
  const [gatewaySaved, setGatewaySaved] = useState(false)

  useEffect(() => {
    void loadAppSettings()
  }, [loadAppSettings])

  useEffect(() => {
    if (appSettings?.gatewayUrl) {
      setGatewayUrl(appSettings.gatewayUrl)
    }
  }, [appSettings?.gatewayUrl])

  const gatewayModeHint = useMemo(() => {
    try {
      const host = new URL(gatewayUrl).hostname.toLowerCase()
      return host === 'localhost' || host === '127.0.0.1' || host === '::1'
        ? 'FreeCAD can use gateway mode with this URL.'
        : 'Remote URLs stay visible, but FreeCAD exports will remain in local mode.'
    } catch {
      return 'Enter a valid URL to control FreeCAD gateway mode.'
    }
  }, [gatewayUrl])

  const saveGatewayUrl = async () => {
    await updateAppSettings({ gatewayUrl })
    setGatewaySaved(true)
    window.setTimeout(() => setGatewaySaved(false), 1600)
  }

  return (
    <div className="p-6 max-w-2xl space-y-6">
      <h1 className="text-xl font-bold">Settings</h1>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between gap-3">
            <div>
              <CardTitle className="text-sm">Factory Gateway</CardTitle>
              <CardDescription>Shared by FreeCAD exports and AI design-review endpoints</CardDescription>
            </div>
            {gatewaySaved && <Badge variant="secondary">Saved</Badge>}
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex gap-2">
            <Input value={gatewayUrl} onChange={e => setGatewayUrl(e.target.value)} placeholder="http://localhost:8001" />
            <Button onClick={() => void saveGatewayUrl()}>Save</Button>
          </div>
          <p className="text-xs text-muted-foreground">
            {gatewayModeHint} Inline schematic review and component suggestions follow this same URL.
          </p>
        </CardContent>
      </Card>

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
