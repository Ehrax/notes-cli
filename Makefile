.PHONY: build release run run-verbose test test-core test-cli test-integration test-e2e proto clean lint setup

# Build
build:
	swift build

release:
	swift build -c release

# Test
test:
	swift test

test-core:
	swift test --filter NotesCoreTests

test-cli:
	swift test --filter NotesCLITests

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
	rm -f ~/.notes-cli/notes.db

clean-cache:
	rm -f ~/.notes-cli/cache/NoteStore.sqlite ~/.notes-cli/cache/NoteStore.sqlite-shm ~/.notes-cli/cache/NoteStore.sqlite-wal

lint:
	swift build 2>&1 | grep -E "warning:|error:" || echo "No lint issues"
