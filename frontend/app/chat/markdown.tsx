import React from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import dynamic from 'next/dynamic'
import { IconCopy, IconCheck } from './icons'

const Mermaid = dynamic(() => import('./Mermaid'), { ssr: false })
const TransformWrapper = dynamic(() => import('react-zoom-pan-pinch').then(mod => mod.TransformWrapper), { ssr: false })
const TransformComponent = dynamic(() => import('react-zoom-pan-pinch').then(mod => mod.TransformComponent), { ssr: false })

export function renderMarkdown(content: string) {
  if (!content) return null

  return (
    <div className="space-y-4">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
        code({ node, className, children, ...props }: any) {
          const match = /language-(\w+)/.exec(className || '')
          
          if (!match) {
            return (
              <code className="px-1.5 py-0.5 rounded text-sm" style={{ background: 'var(--code-bg)', color: 'var(--accent-secondary)' }} {...props}>
                {children}
              </code>
            )
          }

          const lang = match[1]
          const codeStr = String(children).replace(/\n$/, '')

          if (lang === 'mermaid') {
            return <Mermaid chart={codeStr} />
          }

          return (
            <div className="group relative my-4 overflow-hidden rounded-lg border" style={{ borderColor: 'var(--border-color)' }}>
              <div className="flex items-center justify-between px-4 py-1.5 text-xs font-medium" style={{ background: 'var(--bg-surface-hover)', color: 'var(--text-secondary)' }}>
                <span>{lang}</span>
                <CopyButton text={codeStr} />
              </div>
              <pre className="overflow-x-auto p-4 text-sm" style={{ background: 'var(--code-bg)', color: 'var(--text-primary)' }}>
                <code className={className} {...props}>
                  {children}
                </code>
              </pre>
            </div>
          )
        },
        img({ node, src, alt, ...props }: any) {
          return <ChatImage src={src || ''} alt={alt || ''} />
        },
        table({ node, ...props }: any) {
          return (
            <div className="overflow-x-auto my-4 rounded-lg border" style={{ borderColor: 'var(--border-color)' }}>
              <table className="min-w-full border-collapse text-sm text-left" {...props} />
            </div>
          )
        },
        th({ node, ...props }: any) {
          return <th className="border-b px-4 py-3 font-semibold" style={{ borderColor: 'var(--border-color)', background: 'var(--bg-surface-hover)', color: 'var(--text-primary)' }} {...props} />
        },
        td({ node, ...props }: any) {
          return <td className="border-b px-4 py-3" style={{ borderColor: 'var(--border-color)', color: 'var(--text-secondary)' }} {...props} />
        },
        blockquote({ node, ...props }: any) {
          return <blockquote className="border-l-4 pl-4 py-2 my-4 italic" style={{ borderColor: 'var(--accent-primary)', color: 'var(--text-secondary)', background: 'var(--bg-surface-hover)' }} {...props} />
        },
        ul({ node, ...props }: any) {
          return <ul className="ml-5 my-2 list-disc space-y-1" style={{ color: 'var(--text-primary)' }} {...props} />
        },
        ol({ node, ...props }: any) {
          return <ol className="ml-5 my-2 list-decimal space-y-1" style={{ color: 'var(--text-primary)' }} {...props} />
        },
        h1({ node, ...props }: any) { return <h1 className="text-2xl font-bold mt-6 mb-4" style={{ color: 'var(--text-primary)' }} {...props} /> },
        h2({ node, ...props }: any) { return <h2 className="text-xl font-bold mt-5 mb-3" style={{ color: 'var(--text-primary)' }} {...props} /> },
        h3({ node, ...props }: any) { return <h3 className="text-lg font-semibold mt-4 mb-2" style={{ color: 'var(--text-primary)' }} {...props} /> },
        a({ node, href, children, ...props }: any) {
          // Auto-render /docs/ links as images (from KB markdown: [📎 alt](/docs/...))
          if (href && /^\/docs\/.*\.(png|jpe?g|gif|webp|svg)$/i.test(href)) {
            const alt = String(children || '').replace(/^📎\s*/, '')
            return <ChatImage src={href} alt={alt} />
          }
          return <a className="underline hover:opacity-80 transition-opacity" style={{ color: 'var(--accent-primary)' }} target="_blank" rel="noopener noreferrer" href={href} {...props}>{children}</a>
        }
      }}
    >
      {content}
    </ReactMarkdown>
    </div>
  )
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
  const [isZoomed, setIsZoomed] = React.useState(false)
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
          className="fixed inset-0 z-[9999]"
          style={{ background: 'rgba(0, 0, 0, 0.85)' }}
        >
          <button
            className="absolute top-4 right-4 z-[10000] flex h-10 w-10 items-center justify-center rounded-full bg-black/50 text-white text-xl hover:bg-black/70"
            onClick={(e) => { e.stopPropagation(); setIsFullscreen(false); setIsZoomed(false); }}
          >
            ✕
          </button>

          <div className="absolute bottom-6 left-0 right-0 flex justify-center pointer-events-none z-[10000]">
            <div className="bg-black/60 text-white/90 text-sm px-4 py-2 rounded-full backdrop-blur-sm pointer-events-auto shadow-lg">
               Cuộn chuột để Zoom • Kéo để di chuyển
            </div>
          </div>

          <TransformWrapper
            initialScale={1}
            minScale={0.5}
            maxScale={10}
            centerOnInit={true}
            wheel={{ step: 0.1 }}
          >
            <TransformComponent wrapperStyle={{ width: '100vw', height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <img
                src={src}
                alt={alt || ''}
                style={{ 
                  maxWidth: '90vw', 
                  maxHeight: '90vh',
                  objectFit: 'contain',
                  backgroundColor: 'white',
                  padding: '10px',
                  borderRadius: '8px',
                  boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.25)',
                }}
              />
            </TransformComponent>
          </TransformWrapper>
        </div>
      )}
    </>
  )
}
