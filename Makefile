# Makefile for remarkable-mcp Docker image

IMAGE_NAME := remarkable-mcp
IMAGE_TAG := latest
FULL_IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)
CACHE_VOLUME := remarkable-cache

.PHONY: setup register install update verify clean help

# Default target
all: install

#───────────────────────────────────────────────────────────────────────────────
# PUBLIC COMMANDS
#───────────────────────────────────────────────────────────────────────────────

# First-time setup - creates .env and shows instructions
setup:
	@if [ -f .env ]; then \
		echo "⚠️  .env already exists. Delete it first to start fresh."; \
		exit 1; \
	fi
	@cp .env.example .env
	@echo "✓ Created .env from .env.example"
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  GET YOUR API CREDENTIALS"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "1. REMARKABLE TOKEN (required)"
	@echo "   a) Go to: https://my.remarkable.com/device/desktop/connect"
	@echo "   b) Copy the 8-character one-time code"
	@echo "   c) Run: make register"
	@echo "   d) Paste the returned JSON token into .env"
	@echo ""
	@echo "2. GOOGLE VISION API KEY (optional, for handwriting OCR)"
	@echo "   a) Go to: https://console.cloud.google.com/"
	@echo "   b) Enable 'Cloud Vision API'"
	@echo "   c) Create an API key and add to .env"
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  After adding your token to .env, run: make install"
	@echo "═══════════════════════════════════════════════════════════════"

# Register with reMarkable Cloud to get token
register:
	@if ! docker image inspect $(FULL_IMAGE) > /dev/null 2>&1; then \
		echo "Building image first..."; \
		docker build -q -t $(FULL_IMAGE) .; \
	fi
	@echo ""
	@echo "Visit https://my.remarkable.com/device/desktop/connect to get a code"
	@echo ""
	@read -p "Enter your one-time code: " code; \
	docker run --rm -it $(FULL_IMAGE) --register $$code

# Build and install everything
install:
	@echo "Building $(FULL_IMAGE)..."
	@docker build -t $(FULL_IMAGE) .
	@echo "✓ Image built"
	@echo ""
	@echo "Setting up Docker MCP catalog..."
	@if ! docker mcp catalog ls 2>/dev/null | grep -q "^custom:"; then \
		docker mcp catalog create custom > /dev/null 2>&1; \
	fi
	@cp docker-mcp-server.yaml ~/.docker/mcp/catalogs/custom.yaml
	@echo "✓ Catalog configured"
	@echo ""
	@if [ -f .env ]; then \
		echo "Setting up secrets..."; \
		TOKEN=$$(grep REMARKABLE_TOKEN .env | cut -d= -f2-); \
		if [ -n "$$TOKEN" ]; then \
			docker mcp secret set "remarkable.token=$$TOKEN" > /dev/null; \
			echo "✓ remarkable.token set"; \
		fi; \
		GKEY=$$(grep GOOGLE_VISION_API_KEY .env | cut -d= -f2-); \
		if [ -n "$$GKEY" ]; then \
			docker mcp secret set "remarkable.google_vision_key=$$GKEY" > /dev/null; \
			echo "✓ remarkable.google_vision_key set"; \
		fi; \
	else \
		echo "⚠ No .env file - run 'make setup' first to configure secrets"; \
	fi
	@docker volume create $(CACHE_VOLUME) > /dev/null 2>&1 || true
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  ✓ INSTALLED"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "  Next steps:"
	@echo "    1. docker mcp server enable remarkable"
	@echo "    2. Restart your AI client"
	@echo "    3. make verify"
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"

# Rebuild with latest remarkable-mcp from PyPI
update:
	@echo "Rebuilding $(FULL_IMAGE) with latest remarkable-mcp..."
	@docker build --no-cache -t $(FULL_IMAGE) .
	@echo ""
	@echo "✓ Updated to:"
	@docker run --rm $(FULL_IMAGE) --help 2>&1 | head -1 || true

# Verify everything works
verify:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  VERIFICATION"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@# Docker MCP Toolkit
	@printf "Docker MCP Toolkit: "
	@docker mcp version 2>/dev/null && true || echo "✗ Not installed"
	@echo ""
	@# Docker Image
	@printf "Docker Image:       "
	@docker image inspect $(FULL_IMAGE) > /dev/null 2>&1 && echo "✓ $(FULL_IMAGE)" || echo "✗ Not found (run: make install)"
	@echo ""
	@# Server in catalog
	@printf "Server Catalog:     "
	@docker mcp server ls 2>&1 | grep -q "remarkable" && echo "✓ remarkable registered" || echo "✗ Not in catalog"
	@echo ""
	@# Server enabled
	@printf "Server Enabled:     "
	@docker mcp server ls 2>&1 | grep "remarkable" | grep -q -v "^remarkable " 2>/dev/null && echo "✓ Enabled" || echo "⚠ Run: docker mcp server enable remarkable"
	@echo ""
	@# Secrets
	@printf "Secrets:            "
	@docker mcp secret ls 2>&1 | grep -q "remarkable.token" && echo "✓ Token configured" || echo "✗ Missing (run: make install)"
	@echo ""
	@# MCP Response
	@printf "MCP Server:         "
	@if [ -f .env ]; then \
		echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"1.0"}}}' | \
			timeout 15 docker run --rm -i --env-file .env -v $(CACHE_VOLUME):/app/cache $(FULL_IMAGE) 2>/dev/null | \
			grep -q '"serverInfo"' && echo "✓ Responding" || echo "✗ Not responding"; \
	else \
		echo "⚠ No .env file"; \
	fi
	@echo ""
	@# Tools
	@printf "Tools Available:    "
	@if [ -f .env ]; then \
		printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | \
			timeout 20 docker run --rm -i --env-file .env -v $(CACHE_VOLUME):/app/cache $(FULL_IMAGE) 2>/dev/null | \
			grep -q 'remarkable_browse' && echo "✓ 6 tools" || echo "✗ None found"; \
	else \
		echo "⚠ No .env file"; \
	fi
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"

# Remove Docker image and clean up
clean:
	@echo "Cleaning up..."
	@docker rmi $(FULL_IMAGE) 2>/dev/null && echo "✓ Image removed" || echo "  Image not found"
	@docker volume rm $(CACHE_VOLUME) 2>/dev/null && echo "✓ Cache cleared" || echo "  Cache not found"

# Show available commands
help:
	@echo "remarkable-mcp"
	@echo ""
	@echo "Commands:"
	@echo "  make setup     Create .env and show setup instructions"
	@echo "  make register  Get reMarkable Cloud token"
	@echo "  make install   Build and install to Docker MCP"
	@echo "  make update    Rebuild with latest version"
	@echo "  make verify    Check everything works"
	@echo "  make clean     Remove image and cache"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make setup"
	@echo "  2. make register"
	@echo "  3. Add token to .env"
	@echo "  4. make install"
	@echo "  5. docker mcp server enable remarkable"
	@echo "  6. Restart AI client"
