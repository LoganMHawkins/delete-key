# DeleteKey

A tiny background macOS app (no Dock icon, no UI) inspired by [presButan](https://briankendall.net/presButan/index.htm).

In Finder and on the Desktop:

- **Delete / Forward Delete** → Move to Trash (sends ⌘Delete)
- **Return / Enter** → Open (sends ⌘O), opt-in with `--open-with-return`

Keys pass through untouched while you're editing text (renaming, search field).

## Install

```bash
./build.sh --install
```

Builds `DeleteKey.app`, copies it to `~/Applications`, and registers a LaunchAgent so it starts at login. Grant it access in System Settings → Privacy & Security → Accessibility, then restart it:

```bash
launchctl kickstart -k "gui/$(id -u)/ca.theboldbureau.deletekey"
```

To enable Return-to-open, add `--open-with-return` to `ProgramArguments` in `~/Library/LaunchAgents/ca.theboldbureau.deletekey.plist`.

The app is ad-hoc signed, so after a rebuild you may need to remove and re-add it in the Accessibility list.
