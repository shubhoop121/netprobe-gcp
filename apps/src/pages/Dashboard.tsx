import { useEffect, useState } from 'react'
import { Api } from '@/lib/api'
import type { SummaryStats } from '@/lib/types'
import StatCard from '@/components/StatCard'
import { LineChart, Line, CartesianGrid, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import dayjs from 'dayjs'

export default function Dashboard() {
  const [stats, setStats] = useState<SummaryStats | null>(null)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    Api.summary().then(setStats).catch(e=>setErr(String(e)))
  }, [])

  if (err) return <div className="card text-bad">Error: {err}</div>
  if (!stats) return <div className="card">Loading...</div>

  return (
    <div className="space-y-6">
      <div className="grid md:grid-cols-4 gap-4">
        <StatCard label="Connections (24h)" value={stats.total_connections_24h.toLocaleString()} />
        <StatCard label="Alerts (24h)" value={stats.total_alerts_24h.toLocaleString()} tone="warn" />
        <StatCard label="Dropped (24h)" value={stats.dropped_immediate_24h.toLocaleString()} tone="bad" />
        <StatCard label="Durable Blocks" value={stats.blocked_durable_total.toLocaleString()} tone="good" />
      </div>

      <div className="card">
        <div className="text-sm text-zinc-400 mb-3">Timeline (last 24h)</div>
        <div style={{ width: '100%', height: 280 }}>
          <ResponsiveContainer>
            <LineChart data={stats.timeline.map(t=>({ ...t, time: dayjs.unix(t.ts).format('HH:mm') }))}>
              <CartesianGrid stroke="#2a2a2a" />
              <XAxis dataKey="time" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line type="monotone" dataKey="connections" />
              <Line type="monotone" dataKey="alerts" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="card">
        <div className="text-sm text-zinc-400 mb-3">Top Services</div>
        <ul className="grid md:grid-cols-3 gap-2">
          {stats.top_services.map(s => (
            <li key={s.name} className="flex justify-between bg-zinc-900/60 rounded-lg px-4 py-2">
              <span className="text-zinc-300">{s.name}</span>
              <span className="text-zinc-400">{s.count.toLocaleString()}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
