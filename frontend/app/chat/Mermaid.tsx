'use client'

import React, { useEffect, useRef, useState } from 'react'
import mermaid from 'mermaid'

mermaid.initialize({
  startOnLoad: true,
  theme: 'default',
  securityLevel: 'loose',
})

function fixMermaidSyntax(code: string): string {
  let fixed = code.trim();
  
  if ((fixed.includes('->>') || fixed.includes('-->>')) && !/^(sequenceDiagram|graph|flowchart)/i.test(fixed)) {
    fixed = 'sequenceDiagram\n' + fixed;
  }
  
  const lines = fixed.split('\n').map(line => {
    let l = line.trim();
    if (!l) return l;

    // 1. Fix missing target: A->>
    l = l.replace(/(->>|-->>|->|-->)$/, '$1?');
    
    // 2. Fix missing text after colon: A->>B:
    l = l.replace(/(->>|-->>|->|-->)([^:]+):$/, '$1$2: ');
    
    // 3. Fix missing space after colon: A->>B:text
    l = l.replace(/(->>|-->>|->|-->)([^:]+):([^\s])/, '$1$2: $3');
    
    // 4. Fix invalid standalone lines (e.g. "DS: 12. Results") -> "Note over DS: 12. Results"
    // Matches lines that start with Alphanumeric, have a colon, but NO arrows.
    if (/^[A-Za-z0-9_]+:/.test(l) && !l.includes('->') && !l.includes('--')) {
      l = l.replace(/^([A-Za-z0-9_]+):\s*(.*)$/, 'Note over $1: $2');
    }
    
    return l;
  });
  
  return lines.join('\n');
}

export default function Mermaid({ chart }: { chart: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [svgContent, setSvgContent] = useState<string>('')

  useEffect(() => {
    if (!chart) return

    const renderChart = async () => {
      try {
        const id = `mermaid-${Math.random().toString(36).substring(2, 9)}`
        const safeChart = fixMermaidSyntax(chart)
        const { svg } = await mermaid.render(id, safeChart)
        setSvgContent(svg)
        if (ref.current) {
          ref.current.innerHTML = svg
        }
      } catch (error: any) {
        // While streaming, syntax errors are expected. Don't crash, just show raw or wait.
        console.warn('Mermaid render error (likely streaming incomplete):', error?.message || error)
        if (!svgContent && ref.current) {
            // Show raw text temporarily while it's building or if it fails completely
            ref.current.innerHTML = `<pre class="text-xs text-gray-400 overflow-hidden">${chart}</pre>`
        }
      }
    }

    renderChart()
  }, [chart])

  return (
    <>
      <div 
        ref={ref} 
        onClick={() => { if (svgContent) setIsFullscreen(true) }}
        style={{ cursor: svgContent ? 'zoom-in' : 'default' }}
        className="mermaid my-4 flex justify-center overflow-x-auto rounded-lg bg-white p-4 shadow-sm border border-gray-200 dark:bg-gray-800 dark:border-gray-700 hover:shadow-md transition-shadow" 
      />

      {isFullscreen && svgContent && (
        <div
          className="fixed inset-0 z-[9999] flex items-center justify-center p-4"
          style={{ background: 'rgba(0, 0, 0, 0.85)', cursor: 'zoom-out' }}
          onClick={() => setIsFullscreen(false)}
        >
          <button
            className="absolute top-4 right-4 flex h-10 w-10 items-center justify-center rounded-full text-white text-xl hover:bg-white/20"
            onClick={() => setIsFullscreen(false)}
          >
            ✕
          </button>
          <div 
            className="bg-white rounded-xl p-6 w-[95vw] h-[95vh] flex items-center justify-center overflow-auto shadow-2xl mermaid-fullscreen"
            dangerouslySetInnerHTML={{ __html: svgContent }} 
            onClick={(e) => e.stopPropagation()}
            style={{ 
              // Force SVG to be visible and responsive inside the flex container
              display: 'flex'
            }}
          />
          <style dangerouslySetInnerHTML={{__html: `
            .mermaid-fullscreen svg {
              width: 100% !important;
              height: 100% !important;
              max-width: none !important;
            }
          `}} />
        </div>
      )}
    </>
  )
}
