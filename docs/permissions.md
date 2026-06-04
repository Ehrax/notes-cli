# macOS Permissions

notes-cli uses Apple Notes as the source of truth. macOS protects Apple Notes behind two separate permission systems.

## Full Disk Access

Required for read commands:

- `notes list`
- `notes search`
- `notes read`
- `folders`
- `export`

Grant Full Disk Access to the terminal app you use, or to the installed `notes-cli` binary.

Path in System Settings:

```text
Privacy & Security -> Full Disk Access
```

After changing this permission, restart the terminal before trying again.

## Automation

Required for write commands:

- `notes create`
- `notes edit`
- `notes move`
- `notes delete`
- `folder create`
- `folder rename`
- `folder move`
- `folder delete`

macOS should prompt the first time notes-cli asks Notes.app to perform a write. If the prompt was denied, reset or change the permission in:

```text
Privacy & Security -> Automation
```

Look for your terminal app or `notes-cli`, then allow access to Notes.

## Why Both?

Reads open Apple's local Notes database directly in read-only mode. Writes go through ScriptingBridge and Apple Events. These are different macOS permission surfaces, so one can work while the other is still blocked.
