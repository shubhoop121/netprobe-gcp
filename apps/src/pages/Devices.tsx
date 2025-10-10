import { useEffect, useState } from 'react'
import { Api } from '@/lib/api'
import type { Device } from '@/lib/types'
import Table from '@/components/Table'
import { tsToLocal, formatBytes } from '@/lib/utils'

export default function Devices() {
  const [items, setItems] = useState<Device[]>([])
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    Api.devices().then(r=>setItems(r.items)).catch(e=>setErr(String(e)))
  }, [])

  const cols = [
    { key: 'ip', header: 'IP' },
    { key: 'hostname', header: 'Hostname' },
    { key: 'mac', header: 'MAC' },
    { key: 'last_seen', header: 'Last Seen', render: (d: Device)=>tsToLocal(d.last_seen) },
    { key: 'alerts_24h', header: 'Alerts (24h)' },
    { key: 'bytes_tx', header: 'TX', render: (d: Device)=>formatBytes(d.bytes_tx) },
    { key: 'bytes_rx', header: 'RX', render: (d: Device)=>formatBytes(d.bytes_rx) },
  ]

  return (
    <div className="space-y-4">
      <h2 className="text-xl font-semibold">Devices</h2>
      {err && <div className="card text-bad">Error: {err}</div>}
      <Table columns={cols} data={items} keyField="ip" empty="No devices" />
    </div>
  )
}