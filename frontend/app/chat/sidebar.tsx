import { useState, useEffect } from 'react'
import { useTheme } from '@/app/lib/theme-provider'
import { IconPlus, IconMessage, IconTrash, IconLogout, IconSun, IconMoon, IconX } from './icons'

type Conversation = {
  id: string
  title: string
  updatedAt: string
}

type SidebarProps = {
  user: { username: string; role: 'user' | 'admin' }
  conversations: Conversation[]
  activeId: string | null
  isOpen: boolean
  onClose: () => void
  onNew: () => void
  onSelect: (id: string) => void
  onDelete: (id: string) => void
  onLogout: () => void
}

export function ChatSidebar({
  user,
  conversations,
  activeId,
  isOpen,
  onClose,
  onNew,
  onSelect,
  onDelete,
  onLogout,
}: SidebarProps) {
  const { theme, toggleTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  const today = new Date().toDateString()
  const todayConvs = conversations.filter(c => new Date(c.updatedAt).toDateString() === today)
  const earlierConvs = conversations.filter(c => new Date(c.updatedAt).toDateString() !== today)

  return (
    <>
      {/* Mobile overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/50 md:hidden"
          onClick={onClose}
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-72 flex-col transition-transform duration-300 ease-in-out md:static md:translate-x-0
          ${isOpen ? 'translate-x-0' : '-translate-x-full'}`}
        style={{
          background: 'var(--sidebar-bg)',
          borderRight: '1px solid var(--border-color)',
        }}
      >
        <div className="flex items-center justify-between p-4 pb-2">
          <button
            onClick={() => { onNew(); onClose() }}
            className="flex flex-1 items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-medium transition-colors hover:bg-black/5 dark:hover:bg-white/5"
            style={{ color: 'var(--text-primary)', border: '1px solid var(--border-color)' }}
          >
            <IconPlus className="h-4 w-4" />
            Hội thoại mới
          </button>
          <button onClick={onClose} className="ml-2 p-2 md:hidden" style={{ color: 'var(--text-secondary)' }}>
            <IconX className="h-5 w-5" />
          </button>
        </div>

        <nav className="flex-1 overflow-y-auto p-3 pt-0">
          {conversations.length === 0 && (
            <p className="p-4 text-center text-xs" style={{ color: 'var(--text-muted)' }}>
              Chưa có hội thoại nào.
            </p>
          )}

          {todayConvs.length > 0 && (
            <div className="mb-4 mt-2">
              <h3 className="mb-1 px-3 text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-muted)' }}>Hôm nay</h3>
              {todayConvs.map((c) => (
                <ConvItem key={c.id} c={c} isActive={c.id === activeId} onSelect={onSelect} onDelete={onDelete} onClose={onClose} />
              ))}
            </div>
          )}

          {earlierConvs.length > 0 && (
            <div className="mb-4 mt-2">
              <h3 className="mb-1 px-3 text-xs font-semibold uppercase tracking-wider" style={{ color: 'var(--text-muted)' }}>Trước đó</h3>
              {earlierConvs.map((c) => (
                <ConvItem key={c.id} c={c} isActive={c.id === activeId} onSelect={onSelect} onDelete={onDelete} onClose={onClose} />
              ))}
            </div>
          )}
        </nav>

        <div className="p-4" style={{ borderTop: '1px solid var(--border-color)' }}>
          <div className="mb-3 flex items-center justify-between">
            <div className="flex items-center gap-2 overflow-hidden">
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white" style={{ background: 'var(--accent-primary)' }}>
                {user.username.charAt(0).toUpperCase()}
              </div>
              <div className="truncate">
                <div className="truncate text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{user.username}</div>
                <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{user.role}</div>
              </div>
            </div>
            <button
              onClick={toggleTheme}
              className="shrink-0 rounded-lg p-2 transition-colors hover:bg-black/5 dark:hover:bg-white/5"
              style={{ color: 'var(--text-secondary)' }}
              title="Toggle Theme"
            >
              {mounted ? (
                theme === 'dark' ? <IconSun className="h-4 w-4" /> : <IconMoon className="h-4 w-4" />
              ) : (
                <div className="h-4 w-4" />
              )}
            </button>
          </div>
          <button
            onClick={onLogout}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors hover:bg-red-500/10 hover:text-red-500"
            style={{ color: 'var(--text-secondary)' }}
          >
            <IconLogout className="h-4 w-4" />
            Đăng xuất
          </button>
        </div>
      </aside>
    </>
  )
}

function ConvItem({ c, isActive, onSelect, onDelete, onClose }: { c: Conversation; isActive: boolean; onSelect: (id: string) => void; onDelete: (id: string) => void; onClose: () => void }) {
  return (
    <div
      className={`group flex items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors cursor-pointer`}
      style={{
        background: isActive ? 'var(--sidebar-active)' : 'transparent',
        color: isActive ? 'var(--text-primary)' : 'var(--text-secondary)'
      }}
      onClick={() => { onSelect(c.id); onClose() }}
    >
      <IconMessage className="h-4 w-4 shrink-0" />
      <span className="flex-1 truncate">{c.title}</span>
      <button
        onClick={(e) => { e.stopPropagation(); onDelete(c.id) }}
        className="invisible shrink-0 p-1 hover:text-red-500 group-hover:visible"
        title="Xóa"
      >
        <IconTrash className="h-3 w-3" />
      </button>
    </div>
  )
}
