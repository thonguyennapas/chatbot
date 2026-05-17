'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'

import { createSession, deleteSession } from '@/app/lib/session'
import { authenticate } from '@/app/lib/users'

const LoginSchema = z.object({
  username: z.string().min(1, 'Username là bắt buộc.').trim(),
  password: z.string().min(1, 'Password là bắt buộc.'),
})

export type LoginState =
  | {
      errors?: { username?: string[]; password?: string[] }
      message?: string
    }
  | undefined

export async function login(
  _prev: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const parsed = LoginSchema.safeParse({
    username: formData.get('username'),
    password: formData.get('password'),
  })

  if (!parsed.success) {
    return { errors: z.flattenError(parsed.error).fieldErrors }
  }

  const user = await authenticate(parsed.data.username, parsed.data.password)
  if (!user) {
    return { message: 'Sai username hoặc password.' }
  }

  await createSession(user)
  redirect('/chat')
}

export async function logout(): Promise<void> {
  await deleteSession()
  redirect('/login')
}
