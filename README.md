# DeleteKey

A tiny background macOS app (no Dock icon, no UI) inspired by [presButan](https://briankendall.net/presButan/index.htm).

In Finder and on the Desktop:

- **Delete / Forward Delete** → Move to Trash (sends ⌘Delete)
- **Return / Enter** → Open (sends ⌘O), opt-in

Keys pass through untouched while you're editing text (renaming, search field).

Requires macOS 13 or later (Apple Silicon and Intel).

## Install

1. Move `DeleteKey.app` to Applications (or `~/Applications`) and open it.
2. Approve it in System Settings → Privacy & Security → **Accessibility**. This is needed to rewrite key presses. It starts working right after you approve.

It adds itself to Login Items on first launch (turn it off in System Settings → General → Login Items).

### Return opens items (optional)

```bash
defaults write ca.theboldbureau.deletekey openWithReturn -bool true
```

Then quit and reopen DeleteKey. Use `-bool false` to undo.

### Quit / uninstall

```bash
pkill -x DeleteKey
```

Then delete the app and remove it from Login Items and the Accessibility list.

## Build from source

```bash
./build.sh --install   # build, copy to ~/Applications, launch
```

Needs the Xcode command line tools. Signs with an Apple Development certificate if you have one, otherwise ad hoc (ad hoc builds need Accessibility re-approved after every rebuild).

### Release build (maintainers)

```bash
xcrun notarytool store-credentials deletekey-notary --apple-id <id> --team-id <team>   # once
./build.sh --release   # Developer ID sign, notarize, staple → dist/DeleteKey-<version>.zip
```

Needs a *Developer ID Application* certificate. `VERSION=1.1 ./build.sh --release` sets the version.

## Troubleshooting

Log: `~/Library/Logs/DeleteKey.log`. For per-keypress detail: `touch ~/Library/Logs/DeleteKey.debug` (delete the file to turn off).
