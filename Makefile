install:
	swift build -c release
	install .build/release/aiq /usr/local/bin/aiq
