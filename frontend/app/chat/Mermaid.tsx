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
    if (ref.current) {
      mermaid.contentLoaded()
      try {
        const id = `mermaid-${Math.random().toString(36).substring(2, 9)}`
        mermaid.render(id, chart).then(({ svg }) => {
          if (ref.current) ref.current.innerHTML = svg
        })
      } catch (error) {
        console.error('Mermaid render error:', error)
      }
    }
  }, [chart])

  return (
    <div 
      ref={ref} 
      className="mermaid my-4 flex justify-center overflow-x-auto rounded-lg bg-white p-4 shadow-sm border border-gray-200 dark:bg-gray-800 dark:border-gray-700" 
    />
  )
}
