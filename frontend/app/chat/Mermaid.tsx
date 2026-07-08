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

  // 0. Sửa lỗi dính chữ (thiếu xuống dòng trước participant hoặc Note do LLM quên \n)
  // Fix đặc trị cho các ca: "autonumberparticipant", "tạo thanh toánNote over", "AReqNote left of"
  fixed = fixed.replace(/autonumberparticipant/g, 'autonumber\nparticipant');
  fixed = fixed.replace(/([^\n\s])(participant )/g, '$1\n$2');
  fixed = fixed.replace(/([^\n\s])(Note (over|left of|right of|right|left))/g, '$1\n$2');

  // 1. Chống lỗi "got NUM" khi LLM dùng actor bắt đầu bằng số (như 3DS Requestor)
  // Mermaid sẽ crash nếu actor không được bọc ngoặc kép mà lại bắt đầu bằng số.
  fixed = fixed.replace(/3DS\s?Requestor/gi, 'ThreeDS_Requestor');
  fixed = fixed.replace(/3DS\s?Server/gi, 'ThreeDS_Server');
  fixed = fixed.replace(/3DSS/gi, 'ThreeDSS');
  fixed = fixed.replace(/\b3DS\b/gi, 'ThreeDS');
  fixed = fixed.replace(/3D\s?Secure/gi, 'ThreeD_Secure');
  fixed = fixed.replace(/3D-Secure/gi, 'ThreeD_Secure');
  fixed = fixed.replace(/\b1st\b/gi, 'First');
  fixed = fixed.replace(/\b2nd\b/gi, 'Second');
  fixed = fixed.replace(/\b3rd\b/gi, 'Third');

  if ((fixed.includes('->>') || fixed.includes('-->>')) && !/^(sequenceDiagram|graph|flowchart)/i.test(fixed)) {
    fixed = 'sequenceDiagram\n' + fixed;
  }

  const isSequence = /sequenceDiagram/i.test(fixed);
  const validKeywords = /^(participant|actor|Note|loop|alt|opt|else|end|rect|autonumber|title|box|sequenceDiagram|%|par|and|critical|option|break|destroy|link|activate|deactivate)/i;
  
  const processedLines: string[] = [];

  fixed.split('\n').forEach(line => {
    let l = line.trim();
    if (!l) return;

    // 2. Loại bỏ các số/bullet LLM hay tự ý sinh thêm ở đầu câu
    // Xóa "1.", "1.1.", "1)", "2-" (ngay cả khi không có dấu cách)
    l = l.replace(/^((?:\d+[\.\)\-])+)\s*/, '');
    // Xóa số đứng một mình có dấu cách "3 ACS"
    l = l.replace(/^\d+\s+/, '');
    // Xóa "- ", "* " (bắt buộc có dấu cách để không ăn mất "->>")
    l = l.replace(/^[\-\*]\s+/, '');
    
    // Cứu cánh cuối cùng: Nếu dòng vẫn bắt đầu bằng số sau mọi bộ lọc (vd LLM chế ra "5G->>"),
    // Mermaid CHẮC CHẮN sẽ crash. Ta đệm thêm "Actor_" để biến nó thành biến hợp lệ.
    if (/^\d/.test(l)) {
      l = 'Actor_' + l;
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

      processedLines.push(l);
    } else if (!arrowMatch && isSequence) {
      // 5. Lỗi LLM tự chế syntax note: "DS: Results" -> "Note over DS: Results"
      if (/^[A-Za-z0-9_]+:/.test(l) && !l.startsWith('Note ') && !l.startsWith('participant ')) {
        l = l.replace(/^([A-Za-z0-9_]+):\s*(.*)$/, 'Note over $1: $2');
        processedLines.push(l);
      } else if (l.startsWith('Note ')) {
        // 6. Lỗi thiếu text/khoảng trắng sau Note: "Note over A,B:"
        if (!l.includes(':')) l += ': ';
        if (l.endsWith(':')) l += ' ';
        l = l.replace(/(Note [^:]+:)([^\s])/, '$1 $2');
        processedLines.push(l);
      } else if (!validKeywords.test(l)) {
        // CỨU CÁNH TUYỆT ĐỐI: Dòng này KHÔNG có mũi tên, KHÔNG phải keyword hợp lệ.
        // Đây chắc chắn là text rác, danh sách liệt kê, hoặc câu bị rớt dòng từ LLM.
        // Nếu để nguyên, Mermaid sẽ nghĩ đây là Actor mới và crash (got 'NEWLINE') vì thiếu mũi tên.
        // Giải pháp: Nối nó vào cuối dòng trước đó bằng thẻ <br/> để biến thành text đa dòng an toàn.
        if (processedLines.length > 0) {
          processedLines[processedLines.length - 1] += '<br/>' + l;
        } else {
          processedLines.push('% ' + l); // Nếu là dòng đầu tiên thì comment lại
        }
      } else {
        processedLines.push(l);
      }
    } else {
      processedLines.push(l);
    }

    // 7. Fix lỗi dùng ngoặc đơn sai quy tắc trong tên participant (vd: participant A(Merchant))
    if (processedLines.length > 0) {
      const lastIdx = processedLines.length - 1;
      let lastLine = processedLines[lastIdx];
      if (lastLine.startsWith('participant ') && lastLine.includes('(') && !lastLine.includes('"')) {
        processedLines[lastIdx] = lastLine.replace(/\(.*$/, '').trim();
      }
    }
  });

  return processedLines.join('\n');
}

export default function Mermaid({ chart }: { chart: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const [isFullscreen, setIsFullscreen] = useState(false)
  const [isZoomed, setIsZoomed] = useState(false)
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
        onClick={(e) => { 
          if (isFullscreen) {
             // Clicking background closes. Clicking SVG toggles zoom.
             if (e.target === e.currentTarget) {
                 setIsFullscreen(false);
                 setIsZoomed(false);
             } else {
                 setIsZoomed(!isZoomed);
             }
          } else {
             if (svgContent) setIsFullscreen(true);
          }
        }}
        style={{ 
          ...(isFullscreen ? {
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            zIndex: 9999,
            backgroundColor: 'rgba(0,0,0,0.85)',
            display: 'flex', // Flex container for margin auto
            overflow: 'auto',
            margin: 0,
            maxWidth: 'none',
            borderRadius: 0,
            border: 'none',
            cursor: isZoomed ? 'zoom-out' : 'zoom-in',
          } : {
            cursor: svgContent ? 'zoom-in' : 'default',
          })
        }}
        className={!isFullscreen ? 'mermaid my-4 flex justify-center overflow-x-auto rounded-lg bg-white p-4 shadow-sm border border-gray-200 dark:bg-gray-800 dark:border-gray-700 hover:shadow-md transition-shadow' : 'mermaid-fullscreen'}
      />

      {isFullscreen && (
        <>
          <button
            className="fixed top-4 right-4 z-[10000] flex h-10 w-10 items-center justify-center rounded-full text-white text-xl hover:bg-white/20"
            onClick={(e) => { e.stopPropagation(); setIsFullscreen(false); setIsZoomed(false); }}
          >
            ✕
          </button>
          <style dangerouslySetInnerHTML={{
            __html: `
            .mermaid-fullscreen > svg {
              background-color: white !important;
              padding: 20px !important;
              border-radius: 12px !important;
              
              /* Kỹ thuật margin auto trong flex container giúp căn giữa mà ko cắt xén top/left khi cuộn */
              margin: auto !important;
              
              /* Nếu không zoom thì thu nhỏ vừa khít (90vw), nếu zoom thì thả nổi kích thước tự nhiên */
              max-width: ${isZoomed ? 'none' : '90vw'} !important;
              max-height: ${isZoomed ? 'none' : '90vh'} !important;
              
              /* width 100% giúp SVG tự phình ra chạm ngưỡng max-width, khắc phục lỗi SVG biến thành tí hon */
              width: ${isZoomed ? 'max-content' : '100%'} !important;
              height: ${isZoomed ? 'auto' : '100%'} !important;
              
              min-width: ${isZoomed ? 'min(100%, 800px)' : 'auto'} !important;
              
              box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25) !important;
              transition: max-width 0.2s, max-height 0.2s !important;
            }
          `}} />
        </>
      )}
    </>
  )
}
