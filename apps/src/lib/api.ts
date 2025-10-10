import type { Block, Connection, Device, SummaryStats } from './types'

const API_BASE = import.meta.env.VITE_API_BASE || ''

// Generic GET helper with graceful fallback to mock data
async function get<T>(path: string, mock: T): Promise<T> {
  if (!API_BASE) {
    // no backend configured -> return mock
    return new Promise((res) => setTimeout(() => res(mock), 300))
  }
  const r = await fetch(`${API_BASE}${path}`)
  if (!r.ok) {
    throw new Error(`API error: ${r.status} ${r.statusText}`)
  }
  return r.json() as Promise<T>
}

export const Api = {
  async summary(): Promise<SummaryStats> {
    const mock: SummaryStats = (await import('../mock/summary.json')).default
    return get('/stats/summary', mock)
  },
  async logs(params: { q?: string; limit?: number; offset?: number; from?: number; to?: number }): Promise<{ items: Connection[]; total: number }> {
    const mock = (await import('../mock/logs.json')).default
    const query = new URLSearchParams()
    if (params.q) query.set('q', params.q)
    if (params.limit) query.set('limit', String(params.limit))
    if (params.offset) query.set('offset', String(params.offset))
    if (params.from) query.set('ts_from', String(params.from))
    if (params.to) query.set('ts_to', String(params.to))
    return get(`/logs?${query.toString()}`, mock)
  },
  async devices(): Promise<{ items: Device[] }> {
    const mock = (await import('../mock/devices.json')).default
    return get(`/devices`, mock)
  },
  async blocks(): Promise<{ items: Block[] }> {
    const mock = (await import('../mock/blocks.json')).default
    return get(`/policies/blocks`, mock)
  },
  async blockIp(body: { target: string; ttl_minutes?: number; reason?: string }) {
    if (!API_BASE) return { status: 'mocked' }
    const r = await fetch(`${API_BASE}/actions/block`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    return r.json()
  },
  async unblockIp(body: { target: string }) {
    if (!API_BASE) return { status: 'mocked' }
    const r = await fetch(`${API_BASE}/actions/unblock`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    return r.json()
  }
}