import { verifySession } from '@/app/lib/dal'
import { ChatShell } from './chat-shell'

export default async function ChatPage() {
  const session = await verifySession()

  return (
    <ChatShell
      user={{ username: session.username, role: session.role }}
    />
  )
}
