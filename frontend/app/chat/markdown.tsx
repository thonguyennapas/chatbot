import React from 'react'
import { IconCopy, IconCheck } from './icons'

export function renderMarkdown(content: string) {
  if (!content) return null

  // Split by code blocks first, then process inline formatting
  const blocks = content.split(/(```[\s\S]*?```)/)
  
  return blocks.map((block, i) => {
    if (block.startsWith('```') && block.endsWith('```')) {
      const lines = block.slice(3, -3).split('\n')
      const lang = lines[0].trim()
      const code = lines.slice(1).join('\n')
      return (
        <div key={i} className="group relative my-4 overflow-hidden rounded-lg border" style={{ borderColor: 'var(--border-color)' }}>
          {lang && (
            <div className="flex items-center justify-between px-4 py-1.5 text-xs font-medium" style={{ background: 'var(--bg-surface-hover)', color: 'var(--text-secondary)' }}>
              <span>{lang}</span>
              <CopyButton text={code} />
            </div>
          )}
          {!lang && (
            <div className="absolute right-2 top-2 z-10 opacity-0 transition-opacity group-hover:opacity-100">
               <CopyButton text={code} />
            </div>
          )}
          <pre className="overflow-x-auto p-4 text-sm" style={{ background: 'var(--code-bg)', color: 'var(--text-primary)' }}>
            <code>{code}</code>
          </pre>
        </div>
      )
    }

    // Inline formatting
    let html = block
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`(.*?)`/g, '<code class="px-1.5 py-0.5 rounded text-sm" style="background: var(--code-bg); color: var(--accent-secondary)">$1</code>')

    // Parse lines — handle images, lists, and paragraphs
    const lines = html.split('\n')
    const renderedLines = lines.map((line, j) => {
      // Image: ![alt](src)
      const imgMatch = line.match(/!\[([^\]]*)\]\(([^)]+)\)/)
      if (imgMatch) {
        const alt = imgMatch[1]
        const src = imgMatch[2]
        return <ChatImage key={j} src={src} alt={alt} />
      }

      if (line.trim().startsWith('- ')) {
        return <li key={j} className="ml-4 list-disc marker:text-gray-500" dangerouslySetInnerHTML={{ __html: line.replace(/^- /, '') }} />
      }
      if (/^\d+\.\s/.test(line.trim())) {
        return <li key={j} className="ml-4 list-decimal marker:text-gray-500" dangerouslySetInnerHTML={{ __html: line.replace(/^\d+\.\s/, '') }} />
      }
      return <p key={j} className="min-h-[1.5rem]" dangerouslySetInnerHTML={{ __html: line }} />
    })

    return <div key={i} className="space-y-2">{renderedLines}</div>
  })
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = React.useState(false)

  const handleCopy = () => {
    navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <button
      onClick={handleCopy}
      className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs hover:bg-black/10 dark:hover:bg-white/10"
      style={{ color: 'var(--text-muted)' }}
    >
      {copied ? <IconCheck className="h-3 w-3" /> : <IconCopy className="h-3 w-3" />}
      {copied ? 'Copied' : 'Copy'}
    </button>
  )
}

/** Inline image with click-to-zoom fullscreen overlay */
function ChatImage({ src, alt }: { src: string; alt: string }) {
  const [isFullscreen, setIsFullscreen] = React.useState(false)
  const [hasError, setHasError] = React.useState(false)

  if (hasError) {
    return (
      <div
        className="my-3 flex items-center gap-2 rounded-lg border p-3 text-sm"
        style={{ borderColor: 'var(--border-color)', color: 'var(--text-muted)', background: 'var(--bg-surface-2)' }}
      >
        🖼️ <span>{alt || 'Ảnh không tải được'}</span>
      </div>
    )
  }

  return (
    <>
      <figure className="my-3">
        <img
          src={src}
          alt={alt || ''}
          loading="lazy"
          onError={() => setHasError(true)}
          onClick={() => setIsFullscreen(true)}
          className="max-w-full rounded-lg border shadow-sm transition-shadow hover:shadow-md"
          style={{
            borderColor: 'var(--border-color)',
            cursor: 'pointer',
            maxHeight: '400px',
            objectFit: 'contain',
          }}
        />
        {alt && (
          <figcaption className="mt-1.5 text-xs" style={{ color: 'var(--text-muted)' }}>
            {alt}
          </figcaption>
        )}
      </figure>

      {isFullscreen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center"
          style={{ background: 'rgba(0, 0, 0, 0.85)', cursor: 'pointer' }}
          onClick={() => setIsFullscreen(false)}
        >
          <button
            className="absolute top-4 right-4 flex h-10 w-10 items-center justify-center rounded-full text-white text-xl hover:bg-white/20"
            onClick={() => setIsFullscreen(false)}
          >
            ✕
          </button>
          <img
            src={src}
            alt={alt || ''}
            style={{ maxWidth: '95vw', maxHeight: '95vh', objectFit: 'contain' }}
          />
        </div>
      )}
    </>
  )
}
