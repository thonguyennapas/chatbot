'use client'

import React, { useEffect, useRef } from 'react'
import mermaid from 'mermaid'

mermaid.initialize({
  startOnLoad: true,
  theme: 'default',
  securityLevel: 'loose',
})

export default function Mermaid({ chart }: { chart: string }) {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!ref.current || !chart) return

    const renderChart = async () => {
      try {
        const id = `mermaid-${Math.random().toString(36).substring(2, 9)}`
        const { svg } = await mermaid.render(id, chart)
        if (ref.current) {
          ref.current.innerHTML = svg
        }
      } catch (error: any) {
        // While streaming, syntax errors are expected. Don't crash, just show raw or wait.
        console.warn('Mermaid render error (likely streaming incomplete):', error?.message || error)
        if (ref.current && !ref.current.innerHTML) {
            // Show raw text temporarily while it's building or if it fails completely
            ref.current.innerHTML = `<pre class="text-xs text-gray-400 overflow-hidden">${chart}</pre>`
        }
      }
    }

    renderChart()
  }, [chart])

  return (
    <div 
      ref={ref} 
      className="mermaid my-4 flex justify-center overflow-x-auto rounded-lg bg-white p-4 shadow-sm border border-gray-200 dark:bg-gray-800 dark:border-gray-700" 
    />
  )
}
