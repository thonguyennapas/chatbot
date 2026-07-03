#!/bin/bash
# deploy-dify.sh — Deploy Dify self-hosted cho Napas Chatbot
# Usage: bash deploy-dify.sh
#
# Yêu cầu: Docker 24.0+, Docker Compose v2

set -euo pipefail

DIFY_DIR="${HOME}/dify"
DIFY_REPO="https://github.com/langgenius/dify.git"

echo "=========================================="
echo "🚀 Deploy Dify Self-Hosted — Napas Chatbot"
echo "=========================================="

# Step 1: Clone Dify
if [ -d "${DIFY_DIR}" ]; then
    echo "📁 Dify directory already exists at ${DIFY_DIR}"
    echo "   Pulling latest..."
    cd "${DIFY_DIR}" && git pull
else
    echo "📦 Cloning Dify..."
    git clone "${DIFY_REPO}" "${DIFY_DIR}"
fi

cd "${DIFY_DIR}/docker"

# Step 2: Create .env from template
if [ ! -f ".env" ]; then
    echo "⚙️ Creating .env from template..."
    cp .env.example .env

    # Generate secret key
    SECRET_KEY=$(openssl rand -base64 32)
    sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|" .env

    # Set Weaviate as vector store (for Hybrid Search)
    sed -i "s|^VECTOR_STORE=.*|VECTOR_STORE=weaviate|" .env

    echo "✅ .env created. SECRET_KEY generated."
    echo ""
    echo "⚠️  IMPORTANT: Review and edit .env for:"
    echo "   - VECTOR_STORE=weaviate (đã set)"
    echo "   - Ports (default: 80 for nginx)"
    echo "   - Database passwords"
else
    echo "⚙️ .env already exists, skipping..."
fi

# Step 3: Start Dify
echo ""
echo "🐳 Starting Dify containers..."
docker compose up -d

echo ""
echo "=========================================="
echo "✅ Dify deployed!"
echo ""
echo "📍 Admin UI:  http://localhost/install"
echo "   (Tạo admin account lần đầu tiên)"
echo ""
echo "👉 Sau khi tạo account, cấu hình:"
echo "   1. Settings → Model Provider → Add OpenRouter"
echo "   2. Settings → Model Provider → Add Reranking Model"
echo "   3. Create Knowledge Base: napas_tai_lieu_ky_thuat"
echo "      - Chunking: Parent-Child"
echo "      - Index: High Quality"
echo "      - Search: Hybrid"
echo "   4. Create Chatflow: 2 nhánh (KB + Chitchat)"
echo "=========================================="
