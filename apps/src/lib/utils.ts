import dayjs from 'dayjs'

export function tsToLocal(ts: number) {
  return dayjs.unix(ts).format('YYYY-MM-DD HH:mm:ss')
}

export function formatBytes(b?: number | null) {
  if (!b && b !== 0) return '-'
  const units = ['B','KB','MB','GB','TB']
  let i = 0; let val = b as number
  while (val >= 1024 && i < units.length-1) { val/=1024; i++ }
  return `${val.toFixed(1)} ${units[i]}`
}