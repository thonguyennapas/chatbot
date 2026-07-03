import type { Metadata } from 'next'
import { ThemeProvider } from '@/app/lib/theme-provider'
import './globals.css'

export const metadata: Metadata = {
  title: 'NAPAS Internal Chatbot - Trợ lý tài liệu nội bộ',
  description:
    'Chatbot nội bộ NAPAS sử dụng Agentic RAG để tìm kiếm và trả lời dựa trên tài liệu nội bộ. Mỗi câu trả lời kèm trích dẫn nguồn.',
  robots: 'noindex, nofollow',
}

// Inline script to prevent FOUC (flash of unstyled content) on theme load
const themeInitScript = `
  (function() {
    try {
      var t = localStorage.getItem('napas.theme');
      if (t === 'dark' || t === 'light') {
        document.documentElement.setAttribute('data-theme', t);
      } else if (window.matchMedia('(prefers-color-scheme: light)').matches) {
        document.documentElement.setAttribute('data-theme', 'light');
      } else {
        document.documentElement.setAttribute('data-theme', 'dark');
      }
    } catch(e) {
      document.documentElement.setAttribute('data-theme', 'dark');
    }
  })();
`

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="vi" data-theme="dark" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} suppressHydrationWarning />
      </head>
      <body className="min-h-full flex flex-col antialiased" suppressHydrationWarning>
        <ThemeProvider>
          {children}
        </ThemeProvider>
      </body>
    </html>
  )
}
