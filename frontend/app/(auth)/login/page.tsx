import { LoginForm } from './login-form'

export default function LoginPage() {
  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden p-6"
      style={{ background: 'var(--bg-primary)' }}
    >
      {/* Floating orbs background */}
      <div className="orb orb-1" style={{ top: '10%', left: '15%' }} />
      <div className="orb orb-2" style={{ bottom: '15%', right: '10%' }} />
      <div className="orb orb-3" style={{ top: '50%', left: '60%' }} />

      {/* Login card */}
      <div className="glass-card relative z-10 w-full max-w-md p-8 animate-slide-up">
        {/* Logo & branding */}
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-2xl"
            style={{ background: 'linear-gradient(135deg, var(--accent-primary), var(--accent-cta))' }}
          >
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
              <circle cx="12" cy="10" r="1" fill="white" />
              <circle cx="8" cy="10" r="1" fill="white" />
              <circle cx="16" cy="10" r="1" fill="white" />
            </svg>
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
          <p className="mt-1 text-xs" style={{ color: 'var(--text-muted)' }}>
            Sẽ thay bằng SSO/LDAP trong production.
          </p>
        </div>
      </div>
    </main>
  )
}
