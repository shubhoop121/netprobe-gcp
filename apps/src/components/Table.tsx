import { ReactNode } from 'react'

type Col<T> = { key: keyof T | string; header: string; render?: (row: T) => ReactNode; className?: string }
type Props<T> = {
  columns: Col<T>[]
  data: T[]
  keyField: keyof T
  empty?: string
}

export default function Table<T>({ columns, data, keyField, empty='No data' }: Props<T>) {
  return (
    <div className="overflow-x-auto rounded-2xl border border-zinc-800">
      <table className="w-full text-sm">
        <thead className="bg-zinc-900/60">
          <tr>
            {columns.map((c) => (
              <th key={String(c.key)} className={`text-left px-4 py-3 font-medium text-zinc-400 ${c.className||''}`}>{c.header}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.length === 0 && (
            <tr><td className="px-4 py-8 text-center text-zinc-500" colSpan={columns.length}>{empty}</td></tr>
          )}
          {data.map((row) => (
            <tr key={String(row[keyField])} className="odd:bg-zinc-950/60">
              {columns.map((c) => (
                <td key={String(c.key)} className="px-4 py-3 border-t border-zinc-900">
                  {c.render ? c.render(row) : (row as any)[c.key]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
