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
  
  const isSequence = /sequenceDiagram/i.test(fixed);
  
  const lines = fixed.split('\n').map(line => {
    let l = line.trim();
    if (!l) return l;

    // Loại bỏ các số/bullet LLM hay tự ý sinh thêm ở đầu câu (vd "1. A->>B", "- A->>B")
    if (l.match(/^(\d+\.|-|\*)\s+/)) {
      l = l.replace(/^(\d+\.|-|\*)\s+/, '');
    }

    const arrowMatch = l.match(/(->>|-->>|->|-->)/);
    
    if (arrowMatch && isSequence) {
      // 1. Lỗi thiếu target hoàn toàn: "A->>" -> "A->>?"
      if (l.match(/(->>|-->>|->|-->)$/)) {
        l += '?';
      }
      
      // 2. Lỗi thiếu dấu hai chấm (sequence bắt buộc phải có thông điệp): "A->>B" -> "A->>B: "
      const afterArrow = l.substring(l.indexOf(arrowMatch[0]) + arrowMatch[0].length);
      if (!afterArrow.includes(':')) {
        l += ': ';
      }
      
      // 3. Lỗi có dấu hai chấm nhưng không có text/khoảng trắng: "A->>B:" -> "A->>B: "
      if (l.endsWith(':')) {
        l += ' ';
      }
      
      // 4. Lỗi thiếu khoảng trắng sau hai chấm: "A->>B:text" -> "A->>B: text"
      l = l.replace(/(->>|-->>|->|-->)([^:]+):([^\s])/, '$1$2: $3');
      
    } else if (!arrowMatch && isSequence) {
      // 5. Lỗi LLM tự chế syntax note: "DS: Results" -> "Note over DS: Results"
      if (/^[A-Za-z0-9_]+:/.test(l) && !l.startsWith('Note ') && !l.startsWith('participant ')) {
        l = l.replace(/^([A-Za-z0-9_]+):\s*(.*)$/, 'Note over $1: $2');
      }
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
        onClick={() => { if (svgContent) setIsFullscreen(!isFullscreen) }}
        style={{ 
          cursor: svgContent ? (isFullscreen ? 'zoom-out' : 'zoom-in') : 'default',
          ...(isFullscreen ? {
            position: 'fixed',
            top: 0,
            left: 0,
            width: '100vw',
            height: '100vh',
            zIndex: 9999,
            backgroundColor: 'rgba(0,0,0,0.85)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            margin: 0,
            maxWidth: 'none',
            borderRadius: 0,
            border: 'none',
          } : {})
        }}
        className={!isFullscreen ? 'mermaid my-4 flex justify-center overflow-x-auto rounded-lg bg-white p-4 shadow-sm border border-gray-200 dark:bg-gray-800 dark:border-gray-700 hover:shadow-md transition-shadow' : 'mermaid-fullscreen'}
      />

      {isFullscreen && (
        <>
          <button
            className="fixed top-4 right-4 z-[10000] flex h-10 w-10 items-center justify-center rounded-full text-white text-xl hover:bg-white/20"
            onClick={(e) => { e.stopPropagation(); setIsFullscreen(false); }}
          >
            ✕
          </button>
          <style dangerouslySetInnerHTML={{__html: `
            .mermaid-fullscreen > svg {
              background-color: white;
              padding: 1.5rem;
              border-radius: 1rem;
              max-width: 95vw !important;
              max-height: 95vh !important;
              width: auto !important;
              height: auto !important;
              box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
            }
          `}} />
        </>
      )}
    </>
  )
}
