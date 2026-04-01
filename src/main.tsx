import React from 'react'
import ReactDOM from 'react-dom/client'

function App() {
  return (
    <div style={{ padding: 40, fontFamily: 'system-ui' }}>
      <h1>MakeLife Desktop</h1>
      <p>Electron + Vite + React 19 scaffold working.</p>
    </div>
  )
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode><App /></React.StrictMode>
)
