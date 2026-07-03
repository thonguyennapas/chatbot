import 'server-only'

export type DifyStreamRequest = {
  query: string
  conversationId?: string
  user: string
}

type DifyEvent =
  | { event: 'message'; answer: string; conversation_id: string; message_id: string }
  | {
      event: 'message_end'
      conversation_id: string
      message_id: string
      metadata?: {
        retriever_resources?: Array<{
          dataset_name?: string
          document_name?: string
          segment_position?: number
          content?: string
          score?: number
        }>
      }
    }
  | { event: 'error'; status: number; code: string; message: string }
  | { event: string; [key: string]: unknown }

function isMockEnabled(): boolean {
  const base = process.env.DIFY_BASE_URL
  const key = process.env.DIFY_API_KEY
  const flag = process.env.DIFY_USE_MOCK
  if (flag === 'true') return true
  if (!base || !key) return true
  return false
}

export async function streamChat(req: DifyStreamRequest): Promise<ReadableStream<Uint8Array>> {
  if (isMockEnabled()) {
    return buildMockStream(req)
  }
  return callDifyStream(req)
}

async function callDifyStream(req: DifyStreamRequest): Promise<ReadableStream<Uint8Array>> {
  const base = process.env.DIFY_BASE_URL!
  const key = process.env.DIFY_API_KEY!

  const upstream = await fetch(`${base}/v1/chat-messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      query: req.query,
      inputs: {},
      user: req.user,
      conversation_id: req.conversationId ?? '',
      response_mode: 'streaming',
    }),
  })

  if (!upstream.ok || !upstream.body) {
    const detail = await upstream.text().catch(() => '')
    throw new Error(`Dify ${upstream.status}: ${detail.slice(0, 500)}`)
  }

  return upstream.body
}

function buildMockStream(req: DifyStreamRequest): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder()
  const conversationId = req.conversationId || `mock-${Date.now()}`
  const messageId = `msg-${Date.now()}`

  const reply = buildMockReply(req.query)
  const tokens = reply.match(/\S+\s*|\s+/g) ?? [reply]

  return new ReadableStream<Uint8Array>({
    async start(controller) {
      for (const token of tokens) {
        const event: DifyEvent = {
          event: 'message',
          answer: token,
          conversation_id: conversationId,
          message_id: messageId,
        }
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`))
        await sleep(35)
      }

      const end: DifyEvent = {
        event: 'message_end',
        conversation_id: conversationId,
        message_id: messageId,
        metadata: {
          retriever_resources: [
            {
              dataset_name: 'napas-rag-quality-mvp (mock)',
              document_name: 'DOC-MOCK-001',
              segment_position: 1,
              content: 'Đây là chunk giả lập — chưa có RAGFlow thật.',
              score: 0.42,
            },
          ],
        },
      }
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(end)}\n\n`))
      controller.close()
    },
  })
}

function buildMockReply(query: string): string {
  const trimmed = query.trim()
  if (!trimmed) {
    return 'Bạn chưa nhập câu hỏi. Hãy nhập nội dung và gửi lại.'
  }
  return (
    `Đây là phản hồi giả lập (DIFY_USE_MOCK=true hoặc Dify chưa cấu hình).\n\n` +
    `Câu hỏi của bạn: "${trimmed}"\n\n` +
    `Khi Dify Chatflow được cấu hình, câu trả lời thật sẽ kèm trích dẫn từ tài liệu nội bộ. ` +
    `Hiện tại frontend đã streaming token-by-token đúng định dạng Dify SSE.`
  )
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms))
}
