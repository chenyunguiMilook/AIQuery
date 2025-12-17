install:
	swift build -c release
	install .build/release/aiq /usr/local/bin/aiq

install-mcp:
	swift build -c release
	install .build/release/aiq-mcp /usr/local/bin/aiq-mcp
