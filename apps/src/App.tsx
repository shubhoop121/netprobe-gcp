import { NavLink, Outlet } from 'react-router-dom'

export default function App() {
  const nav = [
    { to: '/', label: 'Dashboard' },
    { to: '/logs', label: 'Logs' },
    { to: '/devices', label: 'Devices' },
    { to: '/policies', label: 'Policies' },
    { to: '/settings', label: 'Settings' },
  ]
  return (
    <div>
      <header className="border-b border-zinc-800 sticky top-0 z-50 bg-bg/80 backdrop-blur">
        <div className="container flex items-center justify-between py-4">
          <div className="text-lg font-semibold">NetProbe</div>
          <nav className="flex gap-3">
            {nav.map((n) => (
              <NavLink key={n.to} to={n.to} className={({isActive}) => `btn ${isActive ? 'ring-1 ring-accent' : ''}`} end={n.to === '/'}>
                {n.label}
              </NavLink>
            ))}
          </nav>
        </div>
      </header>
      <main className="container py-6">
        <Outlet />
      </main>
      <footer className="container py-8 text-sm text-zinc-400">
        <p>© {new Date().getFullYear()} NetProbe • Inline IDPS on GCP</p>
      </footer>
    </div>
  )
}