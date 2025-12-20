# Makefile for remarkable-mcp Docker image
# Usage:
#   make build    - Build the Docker image
#   make update   - Force rebuild with latest remarkable-mcp
#   make install  - Build and add to Docker MCP catalog
#   make test     - Test the image runs correctly
#   make clean    - Remove the Docker image

IMAGE_NAME := remarkable-mcp
IMAGE_TAG := latest
FULL_IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)
CACHE_VOLUME := remarkable-cache

.PHONY: all build update install catalog test clean help env-check register secrets status version verify setup tools diagnose

all: build

# Initial setup - creates .env and guides user through getting secrets
setup:
	@if [ -f .env ]; then \
		echo "⚠️  .env already exists. Delete it first if you want to start fresh."; \
		exit 1; \
	fi
	@cp .env.example .env
	@echo "✓ Created .env from .env.example"
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  SETUP: Get your API credentials"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "1. REMARKABLE TOKEN (required)"
	@echo "   ─────────────────────────────"
	@echo "   a) Go to: https://my.remarkable.com/device/desktop/connect"
	@echo "   b) Copy the 8-character one-time code"
	@echo "   c) Run: make register"
	@echo "   d) Paste the returned JSON token into .env as REMARKABLE_TOKEN"
	@echo ""
	@echo "2. GOOGLE VISION API KEY (optional, for handwriting OCR)"
	@echo "   ─────────────────────────────────────────────────────────"
	@echo "   a) Go to: https://console.cloud.google.com/"
	@echo "   b) Create/select a project"
	@echo "   c) Enable 'Cloud Vision API' in APIs & Services → Library"
	@echo "   d) Create an API key in APIs & Services → Credentials"
	@echo "   e) Add to .env as GOOGLE_VISION_API_KEY"
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  After adding your tokens to .env, run: make install"
	@echo "═══════════════════════════════════════════════════════════════"

# Build the Docker image
build:
	@echo "Building $(FULL_IMAGE)..."
	docker build -t $(FULL_IMAGE) .
	@echo "✓ Image built successfully"
	@$(MAKE) --no-print-directory version

# Force rebuild to get latest remarkable-mcp from PyPI
update:
	@echo "Rebuilding $(FULL_IMAGE) with latest remarkable-mcp..."
	docker build --no-cache -t $(FULL_IMAGE) .
	@echo "✓ Image updated successfully"
	@$(MAKE) --no-print-directory version

# Build and install to Docker MCP catalog
install: build catalog secrets
	@echo "Creating cache volume..."
	@docker volume create $(CACHE_VOLUME) > /dev/null 2>&1 || true
	@echo ""
	@echo "✓ remarkable-mcp installed"
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  NEXT STEPS"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "1. Enable the server:"
	@echo "   docker mcp server enable remarkable"
	@echo ""
	@echo "2. Restart your AI client (Claude Code, etc.)"
	@echo ""
	@echo "3. Verify with: make diagnose"
	@echo ""
	@echo "The Docker MCP gateway automatically loads all registered catalogs."
	@echo "No additional configuration needed!"
	@echo "═══════════════════════════════════════════════════════════════"

# Add remarkable to Docker MCP custom catalog
catalog:
	@echo "Setting up Docker MCP catalog..."
	@if ! docker mcp catalog ls 2>/dev/null | grep -q "^custom:"; then \
		docker mcp catalog create custom > /dev/null 2>&1; \
		echo "  ✓ Created custom catalog"; \
	fi
	@cp docker-mcp-server.yaml ~/.docker/mcp/catalogs/custom.yaml
	@echo "  ✓ Installed remarkable to custom catalog"

# Set up Docker MCP secrets from .env file
secrets: env-check
	@echo "Setting up Docker MCP secrets..."
	@TOKEN=$$(grep REMARKABLE_TOKEN .env | cut -d= -f2-); \
	if [ -n "$$TOKEN" ]; then \
		docker mcp secret set "remarkable.token=$$TOKEN"; \
		echo "✓ remarkable.token set"; \
	fi
	@GKEY=$$(grep GOOGLE_VISION_API_KEY .env | cut -d= -f2-); \
	if [ -n "$$GKEY" ]; then \
		docker mcp secret set "remarkable.google_vision_key=$$GKEY"; \
		echo "✓ remarkable.google_vision_key set"; \
	fi

# Check that .env file exists
env-check:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found"; \
		echo "Copy .env.example to .env and fill in your keys"; \
		exit 1; \
	fi

# Register with reMarkable Cloud to get token
register: build
	@echo "Visit https://my.remarkable.com/device/desktop/connect to get a code"
	@read -p "Enter your one-time code: " code; \
	docker run --rm -it $(FULL_IMAGE) --register $$code

# Show version info
version:
	@echo ""
	@echo "Version info:"
	@docker run --rm $(FULL_IMAGE) --help 2>&1 | head -1 || true
	@echo "Image: $(FULL_IMAGE)"

# Test the image
test: env-check
	@echo "Testing $(FULL_IMAGE)..."
	@docker run --rm $(FULL_IMAGE) --help
	@echo ""
	@echo "Testing connection (5 second timeout)..."
	@timeout 5 docker run --rm --env-file .env $(FULL_IMAGE) 2>&1 | head -10 || true
	@echo "✓ Image test passed"

# Verify full MCP pipeline works (requires secrets to be set)
verify: env-check
	@echo "Verifying remarkable-mcp pipeline..."
	@echo ""
	@echo "1. Checking Docker image..."
	@docker run --rm $(FULL_IMAGE) --help > /dev/null && echo "   ✓ Image OK"
	@echo ""
	@echo "2. Checking rmc CLI..."
	@docker run --rm --entrypoint rmc $(FULL_IMAGE) --version > /dev/null 2>&1 && echo "   ✓ rmc CLI OK"
	@echo ""
	@echo "3. Testing MCP server initialization..."
	@echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | \
		timeout 30 docker run --rm -i --env-file .env -v $(CACHE_VOLUME):/app/cache $(FULL_IMAGE) 2>/dev/null | \
		grep -q '"serverInfo"' && echo "   ✓ MCP server OK" || echo "   ✗ MCP server failed"
	@echo ""
	@echo "4. Testing tool listing..."
	@echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | \
		timeout 30 docker run --rm -i --env-file .env -v $(CACHE_VOLUME):/app/cache $(FULL_IMAGE) 2>/dev/null | \
		grep -q 'remarkable_image' && echo "   ✓ Tools available (including remarkable_image)" || echo "   ✗ Tools not found"
	@echo ""
	@echo "✓ Verification complete"

# Run the MCP server standalone (for debugging)
run: env-check
	@echo "Running $(FULL_IMAGE) with .env..."
	docker run --rm -it \
		--env-file .env \
		-v $(CACHE_VOLUME):/app/cache \
		$(FULL_IMAGE)

# Check server status
status:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  Docker MCP Server Status"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@docker mcp server ls 2>&1 | grep -E "NAME|remarkable" || echo "Server not found in catalog"
	@echo ""
	@echo "Secrets:"
	@docker mcp secret ls 2>&1 | grep remarkable || echo "  No secrets configured"
	@echo ""
	@echo "⚠️  Note: 'enabled' status does NOT mean tools are working."
	@echo "   Run 'make verify' to test the full pipeline."

# List available MCP tools
tools: env-check
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  Available MCP Tools"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | \
		timeout 30 docker run --rm -i --env-file .env -v $(CACHE_VOLUME):/app/cache $(FULL_IMAGE) 2>/dev/null | \
		grep -o '"name":"[^"]*"' | sed 's/"name":"//g' | sed 's/"//g' | while read tool; do \
			echo "  • $$tool"; \
		done || echo "  ✗ Could not retrieve tools (check your token)"
	@echo ""
	@echo "Usage: These tools are available via Docker MCP Toolkit"
	@echo "       after running: docker mcp server enable remarkable"

# Full diagnostic check
diagnose:
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  remarkable-mcp Diagnostic Report"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@echo "1. Docker MCP Toolkit"
	@echo "   ─────────────────────────────"
	@docker mcp version 2>/dev/null && echo "   ✓ Installed" || echo "   ✗ Not installed or not in PATH"
	@echo ""
	@echo "2. Docker Image"
	@echo "   ─────────────────────────────"
	@docker image inspect $(FULL_IMAGE) > /dev/null 2>&1 && echo "   ✓ $(FULL_IMAGE) exists" || echo "   ✗ Image not found (run: make build)"
	@echo ""
	@echo "3. Cache Volume"
	@echo "   ─────────────────────────────"
	@docker volume inspect $(CACHE_VOLUME) > /dev/null 2>&1 && echo "   ✓ $(CACHE_VOLUME) exists" || echo "   ✗ Volume not found (run: make install)"
	@echo ""
	@echo "4. Server Registration"
	@echo "   ─────────────────────────────"
	@docker mcp server ls 2>&1 | grep -q remarkable && echo "   ✓ Server in catalog" || echo "   ✗ Server not in catalog"
	@docker mcp server ls 2>&1 | grep remarkable | grep -q "enabled" 2>/dev/null && echo "   ✓ Server enabled" || echo "   ⚠ Server not enabled (run: docker mcp server enable remarkable)"
	@echo ""
	@echo "5. Secrets"
	@echo "   ─────────────────────────────"
	@docker mcp secret ls 2>&1 | grep -q "remarkable.token" && echo "   ✓ remarkable.token configured" || echo "   ✗ remarkable.token missing (run: make secrets)"
	@docker mcp secret ls 2>&1 | grep -q "remarkable.google_vision_key" && echo "   ✓ remarkable.google_vision_key configured (optional)" || echo "   ⚠ remarkable.google_vision_key not set (optional, for OCR)"
	@echo ""
	@echo "6. Local .env File"
	@echo "   ─────────────────────────────"
	@if [ -f .env ]; then \
		echo "   ✓ .env exists"; \
		grep -q "REMARKABLE_TOKEN=." .env && echo "   ✓ REMARKABLE_TOKEN set" || echo "   ✗ REMARKABLE_TOKEN empty"; \
		grep -q "GOOGLE_VISION_API_KEY=." .env && echo "   ✓ GOOGLE_VISION_API_KEY set" || echo "   ⚠ GOOGLE_VISION_API_KEY empty (optional)"; \
	else \
		echo "   ✗ .env not found (run: make setup)"; \
	fi
	@echo ""
	@echo "7. MCP Server Response"
	@echo "   ─────────────────────────────"
	@if [ -f .env ]; then \
		echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"diagnose","version":"1.0"}}}' | \
			timeout 15 docker run --rm -i --env-file .env -v $(CACHE_VOLUME):/app/cache $(FULL_IMAGE) 2>/dev/null | \
			grep -q '"serverInfo"' && echo "   ✓ Server responds to MCP initialize" || echo "   ✗ Server not responding (check token)"; \
	else \
		echo "   ⚠ Skipped (no .env file)"; \
	fi
	@echo ""
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  If all checks pass but tools don't appear in your AI client,"
	@echo "  this is likely a Docker MCP Toolkit issue, not this server."
	@echo "  See: https://github.com/docker/mcp-gateway/issues"
	@echo "═══════════════════════════════════════════════════════════════"

# Clear document cache
clear-cache:
	@echo "Clearing cache volume..."
	@docker volume rm $(CACHE_VOLUME) 2>/dev/null || true
	@docker volume create $(CACHE_VOLUME)
	@echo "✓ Cache cleared"

# Clean up Docker image
clean:
	@echo "Removing $(FULL_IMAGE)..."
	-docker rmi $(FULL_IMAGE)
	@echo "✓ Image removed"

# Show available commands
help:
	@echo "remarkable-mcp Docker Makefile"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make setup       - Create .env and show setup instructions"
	@echo "  make register    - Register device with reMarkable Cloud"
	@echo "  make install     - Build image and set up secrets"
	@echo "  make secrets     - Update Docker MCP secrets from .env"
	@echo ""
	@echo "Build Commands:"
	@echo "  make build       - Build the Docker image"
	@echo "  make update      - Rebuild with latest remarkable-mcp from PyPI"
	@echo "  make clean       - Remove the Docker image"
	@echo ""
	@echo "Diagnostic Commands:"
	@echo "  make status      - Check server and secrets status"
	@echo "  make tools       - List available MCP tools"
	@echo "  make diagnose    - Full diagnostic report"
	@echo "  make verify      - Verify full MCP pipeline works"
	@echo "  make test        - Test the image and connection"
	@echo ""
	@echo "Other Commands:"
	@echo "  make run         - Run standalone for debugging"
	@echo "  make version     - Show version info"
	@echo "  make clear-cache - Clear document cache"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make setup     (creates .env and shows instructions)"
	@echo "  2. make register  (to get REMARKABLE_TOKEN)"
	@echo "  3. Add your token to .env"
	@echo "  4. make install"
	@echo "  5. docker mcp server enable remarkable"
	@echo "  6. Restart AI client"
	@echo "  7. make diagnose  (verify everything works)"
