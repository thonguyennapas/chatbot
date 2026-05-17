import 'server-only'

import { cache } from 'react'
import { redirect } from 'next/navigation'
import { readSession, type SessionPayload } from './session'

export const verifySession = cache(async (): Promise<SessionPayload> => {
  const session = await readSession()
  if (!session?.userId) {
    redirect('/login')
  }
  return session
})

export const getOptionalSession = cache(async (): Promise<SessionPayload | null> => {
  return readSession()
})
