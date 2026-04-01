export function TitleBar() {
  return (
    <div className="h-10 flex items-center px-4 bg-background border-b select-none"
         style={{ WebkitAppRegion: 'drag' } as React.CSSProperties}>
      <div className="ml-20 text-sm text-muted-foreground font-medium">
        MakeLife Desktop
      </div>
    </div>
  )
}
