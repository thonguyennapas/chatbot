# Agentic RAG System — Build Plan cho Napas Internal Chatbot

---

## 1. Tổng Quan Hệ Thống

Đây là kiến trúc **Agentic RAG** thế hệ mới (2026), không phải RAG truyền thống. Hệ thống được thiết kế theo nguyên tắc phân tầng rõ ràng:

> **RAGFlow = Memory** → **Dify = Brain** → **Custom Website = Face**

Khác với RAG cũ (query → retrieve → generate), Agentic RAG có khả năng lập kế hoạch, tự đánh giá kết quả, thực thi multi-step, và phản ứng với sự kiện chủ động mà không cần user trigger.[cite:75][cite:80]

---

## 2. Kiến Trúc 4 Tầng

### Tầng 1 — Memory: RAGFlow (Document Engine)

**Vai trò:** Xử lý, phân tích, lưu trữ toàn bộ tài liệu nội bộ.

**Chức năng chính:**
- Layout-aware parsing: hiểu cấu trúc bảng Excel, cột/hàng, merge cell, footnote PDF[cite:41]
- GraphRAG: xây knowledge graph từ tài liệu, cho phép trả lời câu hỏi cross-document
- Multimodal: OCR ảnh, extract caption, xử lý diagram
- Built-in vector store với hybrid search (dense + sparse)
- Expose External Knowledge Base API để Dify kết nối

**Loại file hỗ trợ:** `.docx`, `.xlsx`, `.pdf`, `.png`, `.jpg`, `.pptx`, `.txt`, `.md`, `.html`

**Deploy:**
```bash
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/docker
docker compose up -d
# Truy cập: http://localhost:80
```

---

### Tầng 2 — Brain: Dify (Orchestration & Agentic Logic)

**Vai trò:** Não bộ của hệ thống — lập kế hoạch, điều phối, thực thi workflow, xử lý sự kiện.

**Chức năng chính:**

| Tính năng | Mô tả | Ứng dụng Napas |
|---|---|---|
| Visual Workflow Builder | Dựng logic không cần code | Thay đổi flow không cần redeploy website |
| External KB (RAGFlow) | Kết nối RAGFlow làm knowledge source | Toàn bộ tài liệu nội bộ |
| ReAct Agent | Reason → Act → Observe → Repeat | Câu hỏi phức tạp multi-hop |
| Webhook Trigger | Nhận HTTP event từ hệ thống ngoài | Core banking push event → AI xử lý |
| Schedule Trigger | Cron job tự động | Auto re-index tài liệu mới hàng đêm |
| Plugin Trigger | Kết nối Slack, Jira, email | Notification khi có câu hỏi chưa trả lời |
| Multi-app | Mỗi phòng ban 1 chatbot riêng | IT, Pháp chế, Kế toán, R&D |
| Monitoring | Token usage, latency, conversation logs | Audit trail, báo cáo sử dụng |

**Kết nối RAGFlow vào Dify:**
```
Dify Admin → Knowledge → External Knowledge API → Add
Endpoint:  http://<ragflow-host>:9380/api/v1/dify
API Key:   <ragflow-api-key>
```

**Deploy:**
```bash
git clone https://github.com/langgenius/dify.git
cd dify/docker
cp .env.example .env
docker compose up -d
# Truy cập: http://localhost:3000
```

---

### Tầng 3 — Face: Custom Website (Next.js)

**Vai trò:** Giao diện người dùng hoàn toàn tùy chỉnh theo branding Napas. User không bao giờ thấy Dify.[cite:60][cite:71]

**Stack đề xuất:**
- **Framework:** Next.js (App Router)
- **UI:** Native HTML/CSS + Tailwind (Tùy biến giao diện, không phụ thuộc UI Library)
- **AI Streaming:** Custom SSE Parsing (fetch & TextDecoder tối ưu bắt luồng từ Dify)
- **Auth:** Custom JWT Session (sử dụng thư viện `jose`, sẵn sàng móc nối SSO sau này)
- **Deploy:** Docker self-hosted hoặc VPS nội bộ

**Core integration (Next.js → Dify API):**
```typescript
// app/api/chat/route.ts
export async function POST(req: Request) {
  const { message, conversationId, userId } = await req.json();

  const response = await fetch(`${process.env.DIFY_BASE_URL}/v1/chat-messages`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${process.env.DIFY_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: message,
      conversation_id: conversationId,
      response_mode: "streaming",
      user: userId,
    }),
  });

  return new Response(response.body, {
    headers: { "Content-Type": "text/event-stream" },
  });
}
```

**Tính năng website cần xây:**
- Chat interface với streaming response
- Upload tài liệu → tự động gửi vào RAGFlow
- Phân quyền theo phòng ban (mỗi phòng chỉ thấy KB của mình)
- Conversation history, đánh giá câu trả lời (thumbs up/down)
- Admin panel: quản lý user, xem logs, cấu hình KB

---

### Tầng 4 — LLM Engine (Reasoning)

**Lựa chọn theo use case (Thông qua OpenRouter LLM Gateway):**

| Use Case | Model | Lý do |
|---|---|---|
| Tài liệu văn bản dài (hợp đồng, quy định) | Claude 4.6 Sonnet | Context lớn, reasoning mạnh |
| Ảnh, diagram, biểu đồ, Excel có chart | Gemini 2.5 Pro Vision | Multimodal tốt nhất 2026[cite:39] |
| Self-host / air-gap (dữ liệu tối mật) | Qwen2-VL-72B (local GPU) | Open source, chạy offline hoàn toàn |
| Chi phí tối ưu (câu hỏi đơn giản) | Llama-3 / Haiku (via OpenRouter)| Tốc độ cao, tối ưu chi phí routing |

### Tầng 5 — LLM Gateway & Security (OpenRouter & API Gateway)

Để đảm bảo tính linh hoạt, tối ưu chi phí và bảo mật cấp doanh nghiệp cho Napas:

**1. LLM Routing qua OpenRouter:**
- **Single Endpoint:** Dify kết nối qua chuẩn OpenAI API của OpenRouter để truy cập toàn bộ model (Claude, Gemini, Llama) mà không cần quản lý nhiều API Keys riêng lẻ.
- **Fallback Mechanism:** Thiết lập tự động fallback trong Dify. Nếu `Claude 4.6 Sonnet` bị rate limit hoặc lỗi, tự động chuyển sang `Gemini 2.5 Pro`, đảm bảo High Availability (99.99%) cho hệ thống nội bộ.
- **Cost Routing:** Định tuyến thông minh theo agent logic: Câu hỏi thường gọi model tối ưu chi phí, tác vụ phân tích tài liệu phức tạp gọi model cao cấp.

**2. Bảo mật Enterprise:**
- **Data Privacy Classifier:** Thêm luồng phân loại dữ liệu. Nếu phát hiện dữ liệu PII/tuyệt mật, hệ thống ép buộc (force-route) truy vấn chạy qua Local Model (Qwen2) thay vì OpenRouter.
- **Internal API Gateway:** Các Tool/Action của Dify khi gọi vào hệ thống nội bộ Napas phải đi qua API Gateway (Kong/APISIX) để chặn RBAC và lưu Audit Log.

---

## 3. Sơ Đồ Luồng Dữ Liệu

### Luồng Ingestion (Upload tài liệu)
```
Admin upload file (docx/xlsx/pdf/ảnh)
    │
    ▼
RAGFlow — Layout-aware parsing
    │     → Chunking thông minh (theo cấu trúc, không cắt ngẫu nhiên)
    │     → Build knowledge graph
    │     → Embedding (Cohere Embed v4 hoặc text-embedding-3-large)
    ▼
Vector Store (Milvus/Elasticsearch tích hợp trong RAGFlow)
    │
    ▼
Sẵn sàng để Dify query
```

### Luồng Chat (User hỏi)
```
User gõ câu hỏi trên Website
    │
    ▼
Next.js API Route → Dify Chat API (streaming)
    │
    ▼
Dify Agent (ReAct loop):
    1. Phân tích câu hỏi — cần gì?
    2. Query RAGFlow External KB
    3. Đánh giá kết quả — đủ không?
    4. Nếu không đủ → Reformulate → Retry (tối đa 3 lần)
    5. Nếu đủ → Generate response bằng LLM
    6. Stream về website → User thấy ngay
```

### Luồng Event-Driven (Chủ động)
```
Sự kiện bên ngoài (core banking, Jira, schedule)
    │
    ▼
Dify Webhook / Schedule / Plugin Trigger
    │
    ▼
Dify Workflow tự động chạy:
    → Query RAGFlow để lấy context liên quan
    → LLM phân tích, tổng hợp
    → Push kết quả qua Slack / Email / API nội bộ
```

---

## 4. Agentic RAG Patterns Được Triển Khai

### Pattern 1: ReAct (Reason + Act)
Agent không trả lời ngay — nó *suy nghĩ* trước: cần retrieve gì, từ đâu, bao nhiêu lần. Cực kỳ hiệu quả cho câu hỏi phức tạp như "So sánh chính sách thanh toán quốc tế năm 2023 và 2025".[cite:75][cite:82]

### Pattern 2: Self-RAG / CRAG (Corrective RAG)
Sau khi retrieve, agent tự đánh giá: kết quả có đủ relevance không? Nếu không → tự sửa query, thử lại. Tránh được vấn đề RAG trả về kết quả không liên quan mà vẫn generate.[cite:83][cite:84]

### Pattern 3: Multi-hop Retrieval
Một câu hỏi phức tạp được chia thành nhiều sub-query liên tiếp. Ví dụ: "Quy trình phê duyệt khoản vay FDI" → Hop 1: quy trình phê duyệt → Hop 2: định nghĩa doanh nghiệp FDI → Hop 3: ngoại lệ áp dụng → Tổng hợp.[cite:76][cite:88]

### Pattern 4: Tool Use + Action
Không chỉ retrieve text — agent có thể gọi API hệ thống nội bộ Napas, query database, tìm kiếm web, gửi notification. Đây là bước chuyển từ "chatbot trả lời" sang "AI agent hành động".[cite:79][cite:80]

### Pattern 5: Proactive / Event-Driven
Agent không cần chờ user hỏi. Khi có sự kiện (file mới, transaction bất thường, deadline đến), hệ thống tự chạy workflow, tổng hợp thông tin, gửi alert.[cite:64][cite:70]


---

## 7. Rủi Ro & Giải Pháp

| Rủi ro | Mức độ | Giải pháp |
|---|---|---|
| RAGFlow chunking kém với Excel phức tạp | Trung bình | Dùng MinerU pre-processing trước khi đưa vào RAGFlow |
| Dify và RAGFlow conflict port khi deploy cùng server | Thấp | Map port khác nhau trong docker-compose |
| LLM hallucination khi tài liệu mâu thuẫn nhau | Cao | Implement CRAG pattern, luôn cite nguồn trong response |
| Latency cao khi ảnh/multimodal | Trung bình | Cache kết quả, tối ưu chunk size, async processing |
| Dữ liệu nhạy cảm gửi ra LLM API bên ngoài | Cao | Dùng Qwen2-VL-72B local cho tài liệu tối mật |

---

## 8. Tech Stack Tóm Tắt

```
LAYER          TECHNOLOGY              ROLE
─────────────────────────────────────────────────────
Face           Next.js                 Custom UI/UX
               Native HTML + CSS       Component library
               Custom SSE Parsing      Streaming chat
               Custom JWT (jose)       Auth / Session

Brain          Dify (self-hosted)      Agent orchestration
               Dify Workflow           Visual logic builder
               Dify Webhook/Schedule   Event-driven triggers

Memory         RAGFlow (self-hosted)   Document processing
               Milvus (built-in)       Vector storage
               GraphRAG (built-in)     Knowledge graph

LLM Gateway    OpenRouter API          Unified API, Fallback & Cost Routing
LLM            Claude 4.6 Sonnet       Text-heavy documents
               Gemini 2.5 Pro Vision   Multimodal (ảnh, chart)
               Qwen2-VL-72B (Local)    Self-hosted cho dữ liệu nhạy cảm

Embedding      Cohere Embed v4         Multimodal embedding
               text-embedding-3-large  Fallback option

Evaluation     RAGAS                   RAG quality metrics
```

---

*Plan này áp dụng kiến trúc Agentic RAG theo các nghiên cứu và best practices mới nhất năm 2026.[cite:85][cite:88]*
