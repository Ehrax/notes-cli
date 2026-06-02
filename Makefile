.PHONY: build release install run run-verbose test test-core test-cli test-integration test-e2e proto clean lint setup

PREFIX ?= /usr/local

# Build
build:
	swift build

release:
	swift build -c release

# Install the release binary so `notes-cli` is callable globally.
# Override the location with: make install PREFIX=$HOME/.local
install: release
	install -d "$(PREFIX)/bin"
	install .build/release/notes-cli "$(PREFIX)/bin/notes-cli"
	@echo "Installed notes-cli to $(PREFIX)/bin/notes-cli"

# Test
test:
	# CLI test suites redirect the process-global stdout fd and share the
	# ServiceContainer singleton, so they are not safe under the parallel
	# test scheduler — run serially to avoid a MainActor-starvation deadlock.
	swift test --no-parallel

test-core:
	swift test --filter NotesCoreTests

test-cli:
	swift test --filter NotesCLITests --no-parallel

test-integration:
	swift test --filter NotesIntegrationTests

test-e2e:
	swift test --filter NotesE2ETests

# Codegen
proto:
	@mkdir -p Sources/NotesCore/Protobuf
	protoc --swift_out=Sources/NotesCore/Protobuf/ --proto_path=Proto/ Proto/notestore.proto
	@echo "Generated Sources/NotesCore/Protobuf/notestore.pb.swift"

# Setup (one-time)
setup:
	swift package resolve
	@command -v protoc >/dev/null || (echo "Install protoc: brew install protobuf swift-protobuf" && exit 1)
	@$(MAKE) proto
	@echo "Setup complete. Run 'make build' to compile."

# Maintenance
clean:
	swift package clean
	rm -f Sources/NotesCore/Protobuf/notestore.pb.swift

lint:
	swift build 2>&1 | grep -E "warning:|error:" || echo "No lint issues"
