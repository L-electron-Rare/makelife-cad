import React, { lazy, Suspense } from 'react'
import ReactDOM from 'react-dom/client'
import { TitleBar } from './components/layout/TitleBar'
import { Sidebar } from './components/layout/Sidebar'
import { StatusBar } from './components/layout/StatusBar'
import { useUIStore } from './stores/ui'
import './styles/globals.css'

const Dashboard = lazy(() => import('./pages/Dashboard'))
const Explorer = lazy(() => import('./pages/Explorer'))
const FreeCAD = lazy(() => import('./pages/FreeCAD'))
const Git = lazy(() => import('./pages/Git'))
const CI = lazy(() => import('./pages/CI'))
const AI = lazy(() => import('./pages/AI'))
const Firmware = lazy(() => import('./pages/Firmware'))
const SettingsPage = lazy(() => import('./pages/Settings'))

const PAGE_MAP = {
  dashboard: Dashboard,
  explorer: Explorer,
  freecad: FreeCAD,
  git: Git,
  ci: CI,
  ai: AI,
  firmware: Firmware,
  settings: SettingsPage,
} as const

function App() {
  const activePage = useUIStore((s) => s.activePage)
  const Page = PAGE_MAP[activePage]

  return (
    <div className="h-screen flex flex-col">
      <TitleBar />
      <div className="flex-1 flex overflow-hidden">
        <Sidebar />
        <main className="flex-1 overflow-auto">
          <Suspense fallback={<div className="p-4 text-muted-foreground">Loading...</div>}>
            <Page />
          </Suspense>
        </main>
      </div>
      <StatusBar />
    </div>
  )
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode><App /></React.StrictMode>
)
