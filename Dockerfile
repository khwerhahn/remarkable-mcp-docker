# Dockerfile for remarkable-mcp
# Builds an optimized image for Docker MCP Toolkit
#
# Key dependencies:
#   remarkable-mcp - MCP server for reMarkable Cloud API
#   rmc - CLI tool to convert .rm files to SVG/PNG (required for remarkable_image)
#   cairosvg - Convert SVG to PNG for image rendering
#
# Rendering pipeline: .rm → rmc → SVG → cairosvg → PNG → OCR

FROM python:3.11-slim AS builder

# Install uv for fast Python package management
RUN pip install --no-cache-dir uv

# Install remarkable-mcp and notebook rendering dependencies
# - rmc: CLI for converting reMarkable .rm files to SVG/PNG
# - cairosvg: SVG to PNG conversion
RUN uv pip install --system remarkable-mcp rmc cairosvg

# --- Final stage ---
FROM python:3.11-slim

LABEL org.opencontainers.image.source="https://github.com/SamMorrowDrums/remarkable-mcp"
LABEL org.opencontainers.image.description="reMarkable MCP Server for Docker MCP Toolkit"
LABEL org.opencontainers.image.title="remarkable-mcp"

# Install runtime dependencies only
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-client \
        # Required for PDF/image processing (cairo/pango)
        libcairo2 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libgdk-pixbuf-2.0-0 \
        shared-mime-info \
        # For tesseract OCR fallback
        tesseract-ocr \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy Python packages and CLI tools from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/remarkable-mcp /usr/local/bin/remarkable-mcp
COPY --from=builder /usr/local/bin/rmc /usr/local/bin/rmc

# Create cache directory for document metadata
# This can be mounted as a volume for persistence
RUN mkdir -p /app/cache && chmod 755 /app/cache
ENV REMARKABLE_CACHE_DIR=/app/cache

# Set working directory
WORKDIR /app

# Health check - verify the binary works
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD remarkable-mcp --help > /dev/null 2>&1 || exit 1

# Default entrypoint
ENTRYPOINT ["remarkable-mcp"]

# Default command - stdio transport for MCP
CMD []
