import React from 'react'
import ReactDOM from 'react-dom/client'
import './styles/globals.css'

function App() {
  return (
    <div className="h-screen flex items-center justify-center">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-foreground">MakeLife Desktop</h1>
        <p className="text-muted-foreground mt-2">Electron + Vite + React 19 + Tailwind</p>
      </div>
    </div>
  )
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode><App /></React.StrictMode>
)
