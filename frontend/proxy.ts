import { NextResponse, type NextRequest } from 'next/server'

import { decrypt, SESSION_COOKIE } from '@/app/lib/session'

const PROTECTED_PREFIXES = ['/chat']
const PUBLIC_PATHS = ['/login']

export default async function proxy(req: NextRequest) {
  const path = req.nextUrl.pathname

  const isProtected = PROTECTED_PREFIXES.some((p) => path === p || path.startsWith(`${p}/`))
  const isPublic = PUBLIC_PATHS.includes(path)

  if (!isProtected && !isPublic) {
    return NextResponse.next()
  }

  const token = req.cookies.get(SESSION_COOKIE)?.value
  const session = await decrypt(token)

  if (isProtected && !session?.userId) {
    const url = req.nextUrl.clone()
    url.pathname = '/login'
    return NextResponse.redirect(url)
  }

  if (isPublic && session?.userId) {
    const url = req.nextUrl.clone()
    url.pathname = '/chat'
    return NextResponse.redirect(url)
  }

  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
}
