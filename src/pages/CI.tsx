import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { useProjectStore } from '@/stores/project'

export default function CI() {
  const config = useProjectStore(s => s.config)

  return (
    <div className="p-6 max-w-4xl space-y-4">
      <h1 className="text-xl font-bold">CI/CD Status</h1>
      <p className="text-muted-foreground text-sm">
        MakeLife ships CI workflow templates. Install them into your project's .github/workflows/ directory.
      </p>
      <div className="space-y-3">
        {['makelife-drc.yml', 'makelife-firmware.yml'].map(name => (
          <Card key={name}>
            <CardContent className="p-4 flex items-center gap-4">
              <Badge variant="secondary">{name}</Badge>
              <span className="text-sm text-muted-foreground flex-1">
                {name.includes('drc') ? 'KiCad ERC/DRC check on pull requests' : 'PlatformIO build + test on push'}
              </span>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}
