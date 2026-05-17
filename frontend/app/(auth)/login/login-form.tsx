'use client'

import { useActionState } from 'react'

import { login, type LoginState } from '@/app/actions/auth'

export function LoginForm() {
  const [state, formAction, pending] = useActionState<LoginState, FormData>(
    login,
    undefined,
  )

  return (
    <form action={formAction} className="space-y-5">
      <div>
        <label htmlFor="username" className="mb-1.5 block text-sm font-medium" style={{ color: 'var(--text-secondary)' }}>
          Username
        </label>
        <div className="relative">
          <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ color: 'var(--text-muted)' }}>
              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
              <circle cx="12" cy="7" r="4" />
            </svg>
          </div>
          <input
            id="username"
            name="username"
            autoComplete="username"
            disabled={pending}
            placeholder="Nhập username"
            className="w-full rounded-xl py-2.5 pl-10 pr-3 text-sm outline-none transition-all duration-200"
            style={{
              background: 'var(--input-bg)',
              border: '1px solid var(--input-border)',
              color: 'var(--text-primary)',
            }}
            onFocus={(e) => {
              e.currentTarget.style.borderColor = 'var(--accent-primary)'
              e.currentTarget.style.boxShadow = '0 0 0 3px var(--input-focus-ring)'
            }}
            onBlur={(e) => {
              e.currentTarget.style.borderColor = 'var(--input-border)'
              e.currentTarget.style.boxShadow = 'none'
            }}
          />
        </div>
        {state?.errors?.username && (
          <p className="mt-1.5 text-xs animate-fade-in" style={{ color: 'var(--error-text)' }}>
            {state.errors.username[0]}
          </p>
        )}
      </div>

      <div>
        <label htmlFor="password" className="mb-1.5 block text-sm font-medium" style={{ color: 'var(--text-secondary)' }}>
          Password
        </label>
        <div className="relative">
          <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ color: 'var(--text-muted)' }}>
              <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
          </div>
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            disabled={pending}
            placeholder="Nhập password"
            className="w-full rounded-xl py-2.5 pl-10 pr-3 text-sm outline-none transition-all duration-200"
            style={{
              background: 'var(--input-bg)',
              border: '1px solid var(--input-border)',
              color: 'var(--text-primary)',
            }}
            onFocus={(e) => {
              e.currentTarget.style.borderColor = 'var(--accent-primary)'
              e.currentTarget.style.boxShadow = '0 0 0 3px var(--input-focus-ring)'
            }}
            onBlur={(e) => {
              e.currentTarget.style.borderColor = 'var(--input-border)'
              e.currentTarget.style.boxShadow = 'none'
            }}
          />
        </div>
        {state?.errors?.password && (
          <p className="mt-1.5 text-xs animate-fade-in" style={{ color: 'var(--error-text)' }}>
            {state.errors.password[0]}
          </p>
        )}
      </div>

      {state?.message && (
        <div
          className="rounded-xl px-4 py-3 text-sm animate-fade-in"
          style={{
            background: 'var(--error-bg)',
            border: '1px solid var(--error-border)',
            color: 'var(--error-text)',
          }}
        >
          {state.message}
        </div>
      )}

      <button
        type="submit"
        disabled={pending}
        className="btn-gradient w-full rounded-xl px-4 py-2.5 text-sm"
      >
        {pending ? (
          <span className="flex items-center justify-center gap-2">
            <svg className="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
            Đang đăng nhập...
          </span>
        ) : (
          'Đăng nhập'
        )}
      </button>
    </form>
  )
}
