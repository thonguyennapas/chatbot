import { LoginForm } from './login-form'

export default function LoginPage() {
  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden p-6"
      style={{ background: 'var(--bg-primary)' }}
    >
      {/* Floating orbs background — NAPAS brand colors */}
      <div className="orb orb-1" style={{ top: '10%', left: '15%' }} />
      <div className="orb orb-2" style={{ bottom: '15%', right: '10%' }} />
      <div className="orb orb-3" style={{ top: '50%', left: '60%' }} />

      {/* Login card */}
      <div className="glass-card relative z-10 w-full max-w-md p-8 animate-slide-up">
        {/* NAPAS Logo & branding */}
        <div className="mb-8 text-center">
          <div className="mx-auto mb-5 flex h-20 w-20 items-center justify-center rounded-2xl"
            style={{
              background: 'linear-gradient(135deg, #1B3A73, #00A3E0)',
              boxShadow: '0 8px 24px rgba(27, 58, 115, 0.3)',
            }}
          >
            <img
              src="/logo.png"
              alt="NAPAS Logo"
              className="h-14 w-14"
              style={{ objectFit: 'contain', filter: 'brightness(2)' }}
            />
          </div>
          <h1 className="text-2xl font-semibold" style={{ color: 'var(--text-primary)' }}>
            NAPAS Internal Chatbot
          </h1>
          <p className="mt-2 text-sm" style={{ color: 'var(--text-secondary)' }}>
            Đăng nhập để truy cập trợ lý tài liệu nội bộ
          </p>
        </div>

        <LoginForm />

        <div className="mt-6 text-center">
          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>
            Demo: <code className="rounded px-1.5 py-0.5 text-xs" style={{ background: 'var(--code-bg)', color: 'var(--accent-secondary)' }}>napas-demo</code>
            {' / '}
            <code className="rounded px-1.5 py-0.5 text-xs" style={{ background: 'var(--code-bg)', color: 'var(--accent-secondary)' }}>napas-demo</code>
          </p>
          <p className="mt-3 text-xs" style={{ color: 'var(--text-muted)' }}>
            © {new Date().getFullYear()} NAPAS — National Payment Corporation of Vietnam
          </p>
        </div>
      </div>
    </main>
  )
}
