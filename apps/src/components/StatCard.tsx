type Props = { label: string; value: string | number; sub?: string; tone?: 'good'|'warn'|'bad'|'neutral' }
export default function StatCard({ label, value, sub, tone='neutral' }: Props) {
  const toneMap = {
    good: 'text-good',
    warn: 'text-warn',
    bad: 'text-bad',
    neutral: 'text-zinc-200'
  } as const
  return (
    <div className="card">
      <div className="text-sm text-zinc-400">{label}</div>
      <div className={`text-3xl font-semibold mt-1 ${toneMap[tone]}`}>{value}</div>
      {sub && <div className="text-xs text-zinc-500 mt-2">{sub}</div>}
    </div>
  )
}