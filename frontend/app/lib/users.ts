import 'server-only'

type DemoUser = {
  id: string
  username: string
  passwordPlain: string
  role: 'user' | 'admin'
}

const DEMO_USERS: DemoUser[] = [
  { id: 'u-001', username: 'napas-demo', passwordPlain: 'napas-demo', role: 'user' },
  { id: 'u-002', username: 'napas-admin', passwordPlain: 'napas-admin', role: 'admin' },
]

export async function authenticate(
  username: string,
  password: string,
): Promise<{ id: string; username: string; role: 'user' | 'admin' } | null> {
  const match = DEMO_USERS.find(
    (u) => u.username === username && u.passwordPlain === password,
  )
  if (!match) return null
  return { id: match.id, username: match.username, role: match.role }
}
