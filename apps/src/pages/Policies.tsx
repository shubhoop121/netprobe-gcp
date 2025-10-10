import { useEffect, useState } from 'react'
import { Api } from '@/lib/api'
import type { Block } from '@/lib/types'
import { tsToLocal } from '@/lib/utils'

export default function Policies() {
  const [items, setItems] = useState<Block[]>([])
  const [target, setTarget] = useState('')
  const [ttl, setTtl] = useState(60)
  const [reason, setReason] = useState('Manual block')
  const [msg, setMsg] = useState<string | null>(null)

  async function load() {
    const r = await Api.blocks()
    setItems(r.items)
  }
  useEffect(()=>{ load() }, [])

  async function block() {
    const r = await Api.blockIp({ target, ttl_minutes: ttl, reason })
    setMsg(`Block result: ${JSON.stringify(r)}`)
    setTarget(''); load()
  }
  async function unblock(ip: string) {
    const r = await Api.unblockIp({ target: ip })
    setMsg(`Unblock result: ${JSON.stringify(r)}`)
    load()
  }

  return (
    <div className="space-y-4">
      <h2 className="text-xl font-semibold">Policies & Blocks</h2>

      <div className="card space-y-3">
        <div className="text-sm text-zinc-400">Add Block</div>
        <div className="flex flex-wrap items-center gap-3">
          <input value={target} onChange={e=>setTarget(e.target.value)} placeholder="IP/CIDR or domain" className="input w-64" />
          <input type="number" value={ttl} onChange={e=>setTtl(parseInt(e.target.value||'60'))} className="input w-32" />
          <input value={reason} onChange={e=>setReason(e.target.value)} className="input w-64" />
          <button className="btn" onClick={block}>Block</button>
        </div>
        {msg && <div className="text-xs text-zinc-500">{msg}</div>}
      </div>

      <div className="card">
        <div className="text-sm text-zinc-400 mb-3">Active Blocks</div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-zinc-900/60">
              <tr>
                <th className="text-left px-4 py-3">Type</th>
                <th className="text-left px-4 py-3">Target</th>
                <th className="text-left px-4 py-3">Reason</th>
                <th className="text-left px-4 py-3">Created</th>
                <th className="text-left px-4 py-3">Expires</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {items.map((b, i) => (
                <tr key={i} className="odd:bg-zinc-950/60 border-t border-zinc-900">
                  <td className="px-4 py-3">{b.type}</td>
                  <td className="px-4 py-3">{b.target}</td>
                  <td className="px-4 py-3">{b.reason || '-'}</td>
                  <td className="px-4 py-3">{tsToLocal(b.created_at)}</td>
                  <td className="px-4 py-3">{b.expires_at ? tsToLocal(b.expires_at) : '-'}</td>
                  <td className="px-4 py-3 text-right">
                    <button className="btn" onClick={()=>unblock(b.target)}>Unblock</button>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr><td className="px-4 py-6 text-center text-zinc-500" colSpan={6}>No blocks</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}