install:
	swift build -c release
	install .build/release/aiq /usr/local/bin/aiq

install-mcp:
	swift build -c release
	install .build/release/aiq-mcp /usr/local/bin/aiq-mcp

# Run MCP server using a project root that contains .ai/index.sqlite.
# Usage:
#   make run-mcp                # uses current directory
#   make run-mcp AIQ_PROJECT_ROOT=/path/to/project
AIQ_PROJECT_ROOT ?= $(CURDIR)

run-mcp:
	AIQ_PROJECT_ROOT="$(AIQ_PROJECT_ROOT)" aiq-mcp
