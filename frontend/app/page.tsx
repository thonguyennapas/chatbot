import { redirect } from 'next/navigation'

import { getOptionalSession } from '@/app/lib/dal'

export default async function Home() {
  const session = await getOptionalSession()
  redirect(session?.userId ? '/chat' : '/login')
}
