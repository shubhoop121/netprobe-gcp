export default function Settings() {
  return (
    <div className="space-y-4">
      <h2 className="text-xl font-semibold">Settings</h2>
      <div className="card space-y-2">
        <div className="text-sm text-zinc-400">Environment</div>
        <div className="text-sm">API Base: <code className="bg-zinc-900 px-2 py-1 rounded">{import.meta.env.VITE_API_BASE || '(mock mode — VITE_API_BASE not set)'}</code></div>
        <p className="text-zinc-400 text-sm">
          Set <code className="bg-zinc-900 px-1 py-0.5 rounded">VITE_API_BASE</code> to point the UI at your Flask API service.
        </p>
      </div>
      <div className="card">
        <div className="text-sm text-zinc-400 mb-2">About</div>
        <p className="text-sm text-zinc-300">
          NetProbe UI is a light dashboard for viewing connections, devices, and managing blocks. It supports mock mode when no backend is configured.
        </p>
      </div>
    </div>
  )
}