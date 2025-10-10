import { useState } from 'react'

export default function SearchBar({ onSearch, placeholder='Search...' }: { onSearch: (q: string) => void; placeholder?: string }) {
  const [q, setQ] = useState('')
  return (
    <div className="flex gap-2">
      <input value={q} onChange={(e)=>setQ(e.target.value)} placeholder={placeholder} className="input w-72" />
      <button onClick={()=>onSearch(q)} className="btn">Search</button>
    </div>
  )
}