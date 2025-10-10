export type Connection = {
  ts: number
  uid: string
  source_ip: string
  source_port: number | null
  destination_ip: string
  destination_port: number | null
  proto: string
  service: string | null
  duration: number | null
  orig_bytes: number | null
  resp_bytes: number | null
  conn_state: string
}

export type Device = {
  ip: string
  mac?: string
  hostname?: string
  last_seen: number
  alerts_24h: number
  bytes_tx: number
  bytes_rx: number
}

export type SummaryStats = {
  total_connections_24h: number
  total_alerts_24h: number
  dropped_immediate_24h: number
  blocked_durable_total: number
  top_services: { name: string; count: number }[]
  timeline: { ts: number; connections: number; alerts: number }[]
}

export type Block = {
  type: 'nftables' | 'cloud-armor'
  target: string // ip/cidr/domain
  reason?: string
  created_at: number
  expires_at?: number
}