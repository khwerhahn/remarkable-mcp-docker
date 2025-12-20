# remarkable-mcp-docker

Docker packaging for [remarkable-mcp](https://github.com/SamMorrowDrums/remarkable-mcp) by [Sam Morrow](https://github.com/SamMorrowDrums), optimized for [Docker MCP Toolkit](https://docs.docker.com/ai/mcp-catalog-and-toolkit/).

> **Note:** This repository provides Docker containerization only. The core MCP server is developed and maintained by Sam Morrow. Please report MCP server issues to the [upstream project](https://github.com/SamMorrowDrums/remarkable-mcp/issues).

## Features

- **Cloud API only** - Connects to reMarkable Cloud (SSH/USB mode not supported in container)
- **Multi-stage build** - Smaller final image size
- **Notebook rendering** - Full support for rendering handwritten notebooks to PNG/SVG via `rmc` CLI
- **Handwriting OCR** - Google Vision API for accurate handwriting recognition, Tesseract as fallback
- **Persistent cache** - Document metadata cached across sessions for faster startup
- **Long-lived container** - Keeps running for better performance
- **Health checks** - Built-in Docker health monitoring

> **Note:** This Docker image only supports **Cloud API mode**. SSH mode (direct USB/network connection to your reMarkable) is not supported because the container cannot access host USB devices or local network services. If you need SSH mode, run [remarkable-mcp](https://github.com/SamMorrowDrums/remarkable-mcp) directly on your host.

## Prerequisites

- Docker Desktop 4.48+ with MCP Toolkit enabled
- reMarkable account (for Cloud API access)
- Google Cloud account (optional, for handwriting OCR)

## Quick Start

```bash
# Clone the repo
git clone https://github.com/khwerhahn/remarkable-mcp-docker.git
cd remarkable-mcp-docker

# 1. Run setup (creates .env and shows instructions)
make setup

# 2. Register with reMarkable to get your token
make register
# Enter the code from https://my.remarkable.com/device/desktop/connect

# 3. Copy the returned JSON token to .env as REMARKABLE_TOKEN

# 4. Install (builds image + sets secrets + creates cache volume)
make install

# 5. Enable the server
docker mcp server enable remarkable

# 6. Check status
make status
```

## Getting Your Tokens

### reMarkable Token (Required)

1. Go to https://my.remarkable.com/device/desktop/connect
2. Copy the one-time code (8 characters)
3. Run `make register` and paste the code
4. Copy the returned JSON token to `.env`:
   ```
   REMARKABLE_TOKEN={"devicetoken": "eyJ...", "usertoken": ""}
   ```

### Google Vision API Key (Optional, for OCR)

1. Go to https://console.cloud.google.com/
2. Create or select a project
3. Enable **Cloud Vision API** in APIs & Services → Library
4. Create an API key in APIs & Services → Credentials
5. Add to `.env`:
   ```
   GOOGLE_VISION_API_KEY=AIzaSy...
   ```

## Commands

### Setup
| Command | Description |
|---------|-------------|
| `make setup` | Create .env and show setup instructions |
| `make register` | Register with reMarkable Cloud |
| `make install` | Build image, set up secrets, create cache |
| `make secrets` | Update Docker MCP secrets from .env |

### Build
| Command | Description |
|---------|-------------|
| `make build` | Build the Docker image |
| `make update` | Rebuild with latest remarkable-mcp |
| `make clean` | Remove the Docker image |

### Diagnostics
| Command | Description |
|---------|-------------|
| `make status` | Check server and secrets status |
| `make tools` | List available MCP tools |
| `make diagnose` | Full diagnostic report (recommended) |
| `make verify` | Verify full MCP pipeline works |
| `make test` | Test the image and connection |

### Other
| Command | Description |
|---------|-------------|
| `make run` | Run standalone for debugging |
| `make version` | Show version info |
| `make clear-cache` | Clear document cache |

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `remarkable_browse` | Browse folders and documents |
| `remarkable_read` | Read document content with pagination |
| `remarkable_search` | Search for documents by name |
| `remarkable_recent` | Get recently modified documents |
| `remarkable_status` | Check connection status |
| `remarkable_image` | Export page as PNG/SVG image with OCR |

### Usage Examples

**Browse your library:**
```
remarkable_browse("/")                    # List root folder
remarkable_browse("/Projects")            # List specific folder
remarkable_browse(query="meeting")        # Search by name
```

**Read document content:**
```
remarkable_read("Document Name")          # Read first page
remarkable_read("Document", page=2)       # Read specific page
remarkable_read("Notes", grep="keyword")  # Search within document
```

**Render handwritten notebooks:**
```
remarkable_image("Notebook Name")                    # Get PNG image
remarkable_image("Notes", include_ocr=True)          # With OCR text extraction
remarkable_image("Sketch", output_format="svg")      # Get SVG vector format
```

**Get recent documents:**
```
remarkable_recent()                       # Last 10 modified
remarkable_recent(limit=5, include_preview=True)  # With content preview
```

## VS Code / Cursor Setup

Add to `.vscode/mcp.json`:

```json
{
  "servers": {
    "remarkable": {
      "command": "uvx",
      "args": ["remarkable-mcp"],
      "env": {
        "REMARKABLE_TOKEN": "{\"devicetoken\": \"eyJ...\", \"usertoken\": \"\"}"
      }
    }
  }
}
```

## Claude Desktop Setup

The server is available through Docker MCP gateway after installation.

## Architecture

```
┌─────────────────────────────────────────────┐
│ Docker MCP Gateway                          │
│   └── remarkable-mcp container              │
│       ├── Python 3.11 runtime               │
│       ├── remarkable-mcp from PyPI          │
│       ├── rmc CLI (notebook → SVG/PNG)      │
│       ├── cairosvg (SVG → PNG conversion)   │
│       ├── Tesseract OCR (fallback)          │
│       └── /app/cache (persistent volume)    │
└─────────────────────────────────────────────┘
```

### Rendering Pipeline

```
.rm file → rmc → SVG → cairosvg → PNG → Google Vision OCR → Text
```

## Updating

When a new version of remarkable-mcp is released:

```bash
cd remarkable-mcp-docker

# Rebuild with latest from PyPI (no cache)
make update

# Verify everything still works
make verify
```

The `make update` command rebuilds the image with `--no-cache` to pull the latest remarkable-mcp from PyPI.

## Performance Tips

- **First load is slow** - The server downloads document metadata from reMarkable Cloud on first start
- **Use cache volume** - The `remarkable-cache` Docker volume persists document metadata across restarts
- **Long-lived mode** - Container stays running to avoid repeated startup overhead
- **Clear cache if needed** - Run `make clear-cache` if documents seem out of sync

## Troubleshooting

### Token Issues

**Token expired or invalid?**
```bash
make register
```
Then update `.env` and run `make secrets`.

### Performance

**First load very slow?**
Normal on first run. Document metadata is being downloaded from reMarkable Cloud. Subsequent starts use the cache.

**Clear stale cache:**
```bash
make clear-cache
```

### Docker MCP Toolkit Issues

**Check server status:**
```bash
make status
docker mcp server ls
```

> **Important:** Server showing "enabled" with "✓ done" for secrets does **not** guarantee the tools are working. This only means the configuration is set, not that the connection is active.

**Verify the server actually works:**
```bash
make verify
```
This tests the full MCP pipeline including initialization and tool listing.

**Tools not showing up in your AI client?**

The Docker MCP Toolkit may show the server as enabled but tools might not be exposed to your client. Try:

1. Restart Docker Desktop
2. Disable and re-enable the server:
   ```bash
   docker mcp server disable remarkable
   docker mcp server enable remarkable
   ```
3. Check Docker MCP Toolkit logs in Docker Desktop

**Known Docker MCP Toolkit limitations:**
- `docker mcp server inspect` may return protocol errors
- `docker mcp tools ls` may hang on some setups
- Tool namespace mapping to AI clients can be inconsistent

If you encounter persistent issues with the Docker MCP Toolkit (not the remarkable-mcp server itself), please report them to:
- [Docker MCP Toolkit Issues](https://github.com/docker/mcp-gateway/issues)
- [Docker Community Forums](https://forums.docker.com)

## File Structure

```
remarkable-mcp-docker/
├── Dockerfile              # Multi-stage container build
├── Makefile                # Build/install/update commands
├── tools.json              # Static tool definitions for AI discovery
├── docker-mcp-server.yaml  # MCP catalog entry template
├── .env                    # Your API keys (git-ignored)
├── .env.example            # Template for .env
├── LICENSE                 # MIT License
└── README.md               # This file
```

### Tool Discovery

The `tools.json` file provides static tool definitions that allow AI clients to discover available tools without starting the server. This improves tool discovery speed and helps AI agents understand what each tool does.

## How It Works

The remarkable-mcp server is configured in a custom Docker MCP catalog at:
```
~/.docker/mcp/catalogs/custom.yaml
```

The `make install` command automatically creates this catalog and adds the remarkable server entry.

Key features:
- `longLived: true` - Container persists for faster subsequent calls
- `volumes: remarkable-cache:/app/cache` - Document metadata cached
- Secrets stored in Docker Desktop's secret store

## Contributing

Contributions are welcome and greatly appreciated! Whether it's bug fixes, new features, documentation improvements, or just suggestions - all input helps make this project better.

**Ways to contribute:**

- **Report bugs** - Open an [issue](https://github.com/khwerhahn/remarkable-mcp-docker/issues) with details about the problem
- **Suggest features** - Have an idea? Open an issue to discuss it
- **Submit PRs** - Fork the repo, make your changes, and submit a pull request
- **Improve docs** - Found something unclear? Documentation fixes are always welcome

**Before submitting a PR:**

1. Fork and clone the repository
2. Create a branch for your changes (`git checkout -b feature/my-improvement`)
3. Test your changes with `make verify`
4. Commit with a clear message
5. Push and open a PR

For issues with the core MCP server functionality (not Docker-specific), please report to the [upstream project](https://github.com/SamMorrowDrums/remarkable-mcp/issues).

## Credits

- **[remarkable-mcp](https://github.com/SamMorrowDrums/remarkable-mcp)** by Sam Morrow - The core MCP server this Docker image packages
- **[rmc](https://github.com/ricklupton/rmc)** - CLI tool for converting reMarkable .rm files
- **[Docker MCP Toolkit](https://docs.docker.com/ai/mcp-catalog-and-toolkit/)** - Container orchestration for MCP servers

## License

MIT License - see [LICENSE](LICENSE) file.

This project packages [remarkable-mcp](https://github.com/SamMorrowDrums/remarkable-mcp) which is also MIT licensed.
