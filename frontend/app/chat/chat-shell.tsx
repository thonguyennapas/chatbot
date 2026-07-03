'use client'

import { useCallback, useEffect, useMemo, useRef, useState, useTransition } from 'react'
import { logout } from '@/app/actions/auth'
import { ChatSidebar } from './sidebar'
import { renderMarkdown } from './markdown'
import { IconMenu, IconSend, IconBot, IconDoc, IconChevron } from './icons'

type Citation = {
  documentName?: string
  datasetName?: string
  segmentPosition?: number
  score?: number
  content?: string
}

type Message = {
  id: string
  role: 'user' | 'assistant'
  content: string
  citations?: Citation[]
  pending?: boolean
}

type Conversation = {
  id: string
  title: string
  updatedAt: string
  messages: Message[]
}

const STORAGE_KEY = 'napas.conversations.v1'
const MAX_TITLE_LEN = 60

export function ChatShell({
  user,
}: {
  user: { username: string; role: 'user' | 'admin' }
}) {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [activeId, setActiveId] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [isSidebarOpen, setIsSidebarOpen] = useState(false)
  const [, startLogoutTransition] = useTransition()
  const messageEndRef = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (raw) {
        const parsed = JSON.parse(raw) as Conversation[]
        setConversations(parsed)
        if (parsed.length > 0) setActiveId(parsed[0].id)
      }
    } catch {
      // Ignore
    }
  }, [])

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(conversations))
    } catch {
      // Ignore
    }
  }, [conversations])

  const active = useMemo(
    () => conversations.find((c) => c.id === activeId) ?? null,
    [conversations, activeId],
  )

  useEffect(() => {
    messageEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [active?.messages.length, active?.messages[active.messages.length - 1]?.content])

  const newConversation = useCallback(() => {
    const id = `local-${Date.now()}`
    const conv: Conversation = {
      id,
      title: 'Hội thoại mới',
      updatedAt: new Date().toISOString(),
      messages: [],
    }
    setConversations((prev) => [conv, ...prev])
    setActiveId(id)
    setError(null)
  }, [])

  const deleteConversation = useCallback(
    (id: string) => {
      setConversations((prev) => {
        const next = prev.filter((c) => c.id !== id)
        if (id === activeId) setActiveId(next[0]?.id ?? null)
        return next
      })
    },
    [activeId],
  )

  const handleInput = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setDraft(e.target.value)
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto'
      textareaRef.current.style.height = `${Math.min(textareaRef.current.scrollHeight, 150)}px`
    }
  }

  const sendMessage = useCallback(async () => {
    const text = draft.trim()
    if (!text || sending) return

    let conv = active
    if (!conv) {
      const id = `local-${Date.now()}`
      conv = {
        id,
        title: text.slice(0, MAX_TITLE_LEN),
        updatedAt: new Date().toISOString(),
        messages: [],
      }
      setConversations((prev) => [conv as Conversation, ...prev])
      setActiveId(id)
    }

    const userMsg: Message = { id: `u-${Date.now()}`, role: 'user', content: text }
    const assistantMsg: Message = { id: `a-${Date.now()}`, role: 'assistant', content: '', pending: true }

    const conversationToSend = conv

    setConversations((prev) =>
      prev.map((c) =>
        c.id === conversationToSend.id
          ? {
            ...c,
            messages: [...c.messages, userMsg, assistantMsg],
            title: c.messages.length === 0 ? text.slice(0, MAX_TITLE_LEN) : c.title,
            updatedAt: new Date().toISOString(),
          }
          : c,
      ),
    )
    setDraft('')
    if (textareaRef.current) textareaRef.current.style.height = 'auto'
    setSending(true)
    setError(null)

    try {
      const upstreamConvId = conversationToSend.id.startsWith('local-') ? undefined : conversationToSend.id
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: text, conversationId: upstreamConvId }),
      })

      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`)

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      let assistantText = ''
      let citations: Citation[] | undefined
      let serverConvId: string | undefined

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''

        for (const line of lines) {
          const trimmed = line.trim()
          if (!trimmed.startsWith('data:')) continue
          const payload = trimmed.slice(5).trim()
          if (!payload || payload === '[DONE]') continue

          try {
            const event = JSON.parse(payload)
            if (event.conversation_id) serverConvId = event.conversation_id

            if (event.event === 'message' && typeof event.answer === 'string') {
              assistantText += event.answer
              setConversations((prev) =>
                prev.map((c) =>
                  c.id === conversationToSend.id
                    ? { ...c, messages: c.messages.map((m) => m.id === assistantMsg.id ? { ...m, content: assistantText } : m) }
                    : c
                ),
              )
            } else if (event.event === 'message_end') {
              citations = event.metadata?.retriever_resources?.map((r: any) => ({
                datasetName: r.dataset_name, documentName: r.document_name, segmentPosition: r.segment_position, content: r.content, score: r.score,
              }))
            }
          } catch { continue }
        }
      }

      setConversations((prev) =>
        prev.map((c) => {
          if (c.id !== conversationToSend.id) return c
          const nextId = serverConvId && c.id.startsWith('local-') ? serverConvId : c.id
          return {
            ...c,
            id: nextId,
            messages: c.messages.map((m) =>
              m.id === assistantMsg.id ? { ...m, content: assistantText, citations, pending: false } : m
            ),
            updatedAt: new Date().toISOString(),
          }
        }),
      )
      if (serverConvId && conversationToSend.id.startsWith('local-')) setActiveId(serverConvId)
    } catch (reason) {
      const message = reason instanceof Error ? reason.message : 'Lỗi kết nối.'
      setError(message)
      setConversations((prev) =>
        prev.map((c) =>
          c.id === conversationToSend.id
            ? { ...c, messages: c.messages.map((m) => m.id === assistantMsg.id ? { ...m, content: `[Lỗi: ${message}]`, pending: false } : m) }
            : c
        )
      )
    } finally {
      setSending(false)
    }
  }, [draft, sending, active])

  return (
    <div className="flex h-screen overflow-hidden" style={{ background: 'var(--bg-primary)' }}>
      <ChatSidebar
        user={user}
        conversations={conversations.map(c => ({ id: c.id, title: c.title, updatedAt: c.updatedAt }))}
        activeId={activeId}
        isOpen={isSidebarOpen}
        onClose={() => setIsSidebarOpen(false)}
        onNew={newConversation}
        onSelect={setActiveId}
        onDelete={deleteConversation}
        onLogout={() => startLogoutTransition(() => logout())}
      />

      <main className="flex flex-1 flex-col overflow-hidden relative">
        <header className="flex h-14 items-center gap-3 px-4 md:px-6" style={{ borderBottom: '1px solid var(--border-color)', background: 'var(--bg-surface)' }}>
          <button onClick={() => setIsSidebarOpen(true)} className="p-1 md:hidden" style={{ color: 'var(--text-secondary)' }}>
            <IconMenu className="h-5 w-5" />
          </button>
          <div className="flex-1 truncate font-medium" style={{ color: 'var(--text-primary)' }}>
            {active?.title ?? 'Napas Internal Chatbot'}
          </div>
          <div className="rounded-full px-3 py-1 text-xs font-medium" style={{ background: 'var(--bg-surface-hover)', color: 'var(--accent-secondary)' }}>
            Napas Agent
          </div>
        </header>

        <div className="flex-1 overflow-y-auto px-4 md:px-6">
          {!active || active.messages.length === 0 ? (
            <div className="mx-auto flex h-full max-w-3xl flex-col items-center justify-center p-8 text-center animate-slide-up">
              <div className="mb-6 flex h-20 w-20 items-center justify-center overflow-hidden rounded-2xl shadow-lg border" style={{ background: '#FFFFFF', borderColor: 'var(--border-color)' }}>
                <img src="/logo.png" alt="Napas Logo" className="h-14 w-14 object-contain" />
              </div>
              <h2 className="text-2xl font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Trợ lý Nội bộ NAPAS</h2>
              <p className="max-w-md text-sm mb-10" style={{ color: 'var(--text-secondary)' }}>
                Hỏi đáp dựa trên tài liệu nội bộ, quy trình và chính sách. Thông tin được trích xuất an toàn và bảo mật.
              </p>
              <div className="grid w-full max-w-2xl grid-cols-1 gap-4 md:grid-cols-2 text-left">
                {[
                  { icon: '📋', text: 'Tóm tắt quy trình phát hành thẻ NAPAS.' },
                  { icon: '🔧', text: 'Các lỗi giao dịch phổ biến và cách xử lý?' },
                  { icon: '🔒', text: 'Chính sách bảo mật cho ứng dụng ví điện tử?' },
                  { icon: '🔗', text: 'Chuẩn kết nối API cho ngân hàng thành viên?' }
                ].map((prompt, i) => (
                  <button
                    key={i}
                    onClick={() => { setDraft(prompt.text); setTimeout(() => textareaRef.current?.focus(), 0) }}
                    className="group flex items-start gap-3 rounded-2xl border p-4 text-sm transition-all duration-200 hover:-translate-y-1 hover:shadow-lg cursor-pointer"
                    style={{ background: 'var(--bg-surface)', borderColor: 'var(--border-color)', color: 'var(--text-secondary)' }}
                  >
                    <span className="text-lg mt-0.5 shrink-0 transition-transform duration-200 group-hover:scale-110">{prompt.icon}</span>
                    <span className="leading-relaxed">{prompt.text}</span>
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <div className="mx-auto max-w-3xl pb-6">
              {active.messages.map((m) => (
                <MessageItem key={m.id} message={m} user={user} />
              ))}
              <div ref={messageEndRef} className="h-4" />
            </div>
          )}
        </div>

        <div className="p-4 md:px-6" style={{ background: 'var(--bg-primary)' }}>
          {error && (
            <div className="mx-auto mb-3 max-w-3xl rounded-2xl p-3 text-sm animate-fade-in" style={{ background: 'var(--error-bg)', color: 'var(--error-text)', border: '1px solid var(--error-border)' }}>
              {error}
            </div>
          )}
          <div className="mx-auto max-w-3xl relative">
            <textarea
              ref={textareaRef}
              value={draft}
              onChange={handleInput}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage() } }}
              placeholder="Nhập câu hỏi cho trợ lý..."
              disabled={sending}
              rows={1}
              className="block w-full resize-none rounded-2xl py-3.5 pl-5 pr-14 text-sm outline-none transition-all"
              style={{
                background: 'var(--bg-surface)',
                color: 'var(--text-primary)',
                border: '1px solid var(--border-color)',
                boxShadow: '0 2px 12px rgba(0,0,0,0.06)',
                minHeight: '52px',
                maxHeight: '150px'
              }}
              onFocus={(e) => { e.currentTarget.style.borderColor = 'var(--accent-primary)'; e.currentTarget.style.boxShadow = '0 2px 16px rgba(0,163,224,0.12)' }}
              onBlur={(e) => { e.currentTarget.style.borderColor = 'var(--border-color)'; e.currentTarget.style.boxShadow = '0 2px 12px rgba(0,0,0,0.06)' }}
            />
            <button
              onClick={sendMessage}
              disabled={sending || !draft.trim()}
              title="Gửi tin nhắn"
              className="absolute bottom-2.5 right-2.5 flex h-9 w-9 items-center justify-center rounded-xl transition-all duration-200 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
              style={{
                background: draft.trim() ? 'linear-gradient(135deg, var(--accent-primary), var(--accent-cta))' : 'var(--bg-surface-hover)',
                color: draft.trim() ? '#fff' : 'var(--text-muted)'
              }}
            >
              <IconSend className="h-4 w-4" />
            </button>
          </div>
          <p className="mx-auto max-w-3xl mt-2 text-center text-xs" style={{ color: 'var(--text-muted)' }}>
            Trợ lý AI có thể mắc lỗi. Hãy kiểm chứng thông tin quan trọng.
          </p>
        </div>
      </main>
    </div>
  )
}

function MessageItem({ message, user }: { message: Message; user: { username: string } }) {
  const isUser = message.role === 'user'

  return (
    <div className={`flex w-full py-6 md:px-6 px-4 animate-slide-up`} style={{ background: isUser ? 'transparent' : 'var(--bg-surface)' }}>
      <div className="mx-auto flex w-full max-w-3xl gap-4 md:gap-6">
        <div className="shrink-0 pt-1">
          {isUser ? (
            <div className="flex h-8 w-8 items-center justify-center rounded-full text-xs font-bold text-white shadow-sm" style={{ background: 'var(--accent-primary)' }}>
              {user.username.charAt(0).toUpperCase()}
            </div>
          ) : (
            <div className="flex h-8 w-8 items-center justify-center overflow-hidden rounded-full shadow-sm border" style={{ background: 'var(--bg-surface)', borderColor: 'var(--border-color)' }}>
              <img src="/logo.png" alt="Napas Agent" className="h-5 w-5 object-contain" />
            </div>
          )}
        </div>

        <div className="flex-1 min-w-0">
          <div className="mb-1 font-medium" style={{ color: 'var(--text-primary)' }}>
            {isUser ? 'Bạn' : 'Napas Agent'}
          </div>

          <div className="markdown-content text-[15px] leading-relaxed">
            {isUser ? (
              <p className="whitespace-pre-wrap">{message.content}</p>
            ) : (
              message.content ? renderMarkdown(message.content) : null
            )}

            {message.pending && message.content === '' && (
              <div className="flex h-6 items-center gap-1">
                <div className="typing-dot" />
                <div className="typing-dot" />
                <div className="typing-dot" />
              </div>
            )}
          </div>

          {message.citations && message.citations.length > 0 && (
            <div className="mt-4">
              <details className="group rounded-lg border text-sm" style={{ borderColor: 'var(--border-color)', background: 'var(--bg-surface-2)' }}>
                <summary className="flex cursor-pointer items-center gap-2 p-3 font-medium select-none" style={{ color: 'var(--text-secondary)' }}>
                  <IconDoc className="h-4 w-4" />
                  <span>{message.citations.length} nguồn tham khảo</span>
                  <IconChevron className="h-4 w-4 ml-auto transition-transform group-open:rotate-180" />
                </summary>
                <div className="border-t p-3 space-y-3" style={{ borderColor: 'var(--border-color)' }}>
                  {message.citations.map((c, i) => (
                    <div key={i} className="rounded border p-3" style={{ borderColor: 'var(--border-color-subtle)', background: 'var(--bg-surface)' }}>
                      <div className="mb-2 flex items-center justify-between gap-2">
                        <span className="font-medium truncate" style={{ color: 'var(--text-primary)' }}>{c.documentName || 'Unknown Document'}</span>
                        {c.score && (
                          <span className="shrink-0 rounded px-1.5 py-0.5 text-xs font-medium" style={{ background: 'var(--sidebar-active)', color: 'var(--accent-secondary)' }}>
                            {(c.score * 100).toFixed(0)}% match
                          </span>
                        )}
                      </div>
                      <div className="text-xs line-clamp-3" style={{ color: 'var(--text-muted)' }}>
                        {c.content || 'No content preview available.'}
                      </div>
                    </div>
                  ))}
                </div>
              </details>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
