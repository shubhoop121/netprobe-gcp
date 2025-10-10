import { useEffect, useState } from 'react'
import { Api } from '@/lib/api'
import type { Connection } from '@/lib/types'
import Table from '@/components/Table'
import SearchBar from '@/components/SearchBar'
import { tsToLocal, formatBytes } from '@/lib/utils'

export default function Logs() {
  const [items, setItems] = useState<Connection[]>([])
  const [total, setTotal] = useState(0)
  const [q, setQ] = useState('')
  const [err, setErr] = useState<string | null>(null)

  async function load() {
    try {
      const res = await Api.logs({ q, limit: 100, offset: 0 })
      setItems(res.items)
      setTotal(res.total)
      setErr(null)
    } catch (e:any) { setErr(String(e)) }
  }

  useEffect(()=>{ load() }, [])

  const cols = [
    { key: 'ts', header: 'Time', render: (r: Connection) => tsToLocal(r.ts) },
    { key: 'source_ip', header: 'Source' },
    { key: 'destination_ip', header: 'Destination' },
    { key: 'proto', header: 'Proto' },
    { key: 'service', header: 'Service' },
    { key: 'orig_bytes', header: 'Tx', render: (r: Connection)=>formatBytes(r.orig_bytes??undefined) },
    { key: 'resp_bytes', header: 'Rx', render: (r: Connection)=>formatBytes(r.resp_bytes??undefined) },
    { key: 'conn_state', header: 'State' },
  ]

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">Logs</h2>
        <SearchBar onSearch={(qq)=>{ setQ(qq); load() }} placeholder="IP, UID, service..." />
      </div>
      {err && <div className="card text-bad">Error: {err}</div>}
      <Table columns={cols} data={items} keyField="uid" empty="No logs" />
      <div className="text-sm text-zinc-500">Total: {total.toLocaleString()}</div>
    </div>
  )
}