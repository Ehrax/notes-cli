# Install

notes-cli currently installs from source.

## Requirements

- macOS 13 or newer.
- Xcode command line tools.
- Swift 6.2 toolchain.
- Homebrew packages for protobuf code generation:

```bash
brew install protobuf swift-protobuf
```

## Build And Install

```bash
git clone https://github.com/ehrax/notes-cli.git
cd notes-cli
make setup
make install
```

By default, `make install` copies the release binary to `/usr/local/bin/notes-cli`.

Use a custom prefix if `/usr/local/bin` is not writable:

```bash
make install PREFIX="$HOME/.local"
```

Then make sure the binary directory is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Verify

```bash
notes-cli --version
notes-cli --help
```

Then initialize the config:

```bash
notes-cli init
```

The only notes-cli config file is `~/.notes-cli/config.json`.
