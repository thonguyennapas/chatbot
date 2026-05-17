import { z } from 'zod'

import { verifySession } from '@/app/lib/dal'
import { streamChat } from '@/app/lib/dify'

export const dynamic = 'force-dynamic'

const ChatRequestSchema = z.object({
  message: z.string().min(1).max(4000),
  conversationId: z.string().optional(),
})

export async function POST(request: Request): Promise<Response> {
  const session = await verifySession()

  let body: unknown
  try {
    body = await request.json()
  } catch {
    return Response.json({ error: 'Body phải là JSON.' }, { status: 400 })
  }

  const parsed = ChatRequestSchema.safeParse(body)
  if (!parsed.success) {
    return Response.json(
      { error: 'Payload không hợp lệ.', details: z.flattenError(parsed.error) },
      { status: 400 },
    )
  }

  try {
    const stream = await streamChat({
      query: parsed.data.message,
      conversationId: parsed.data.conversationId,
      user: session.userId,
    })

    return new Response(stream, {
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'X-Accel-Buffering': 'no',
      },
    })
  } catch (reason) {
    const message = reason instanceof Error ? reason.message : 'Lỗi không xác định.'
    return Response.json({ error: message }, { status: 502 })
  }
}
