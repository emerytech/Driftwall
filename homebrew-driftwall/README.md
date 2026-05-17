# homebrew-driftwall

Homebrew tap for [Driftwall](https://github.com/emerytech/Driftwall) — a free video wallpaper app for macOS.

## Install

```sh
brew install --cask emerytech/driftwall/driftwall
```

That's it — Driftwall installs to `/Applications`. Launch it, pick a video (or browse free stock clips), and it becomes your desktop wallpaper. It lives in the menu bar (no Dock icon).

If you're installing an **unsigned** build (the source/ad-hoc release rather than the notarized one), bypass the Gatekeeper quarantine:

```sh
brew install --cask --no-quarantine emerytech/driftwall/driftwall
```

## Updating

```sh
brew update && brew upgrade --cask driftwall
```

## Uninstall

```sh
brew uninstall --cask driftwall          # add --zap to also remove preferences
```

---

## Maintainer notes (this repo)

This repo only needs the `Casks/` directory. To cut a release from the
[Driftwall repo](https://github.com/emerytech/Driftwall):

1. `./release.sh` — builds, (notarizes if creds present), produces
   `dist/Driftwall-<ver>.dmg` + `dist/Driftwall-<ver>.zip`, and
   regenerates `homebrew-driftwall/Casks/driftwall.rb` with the right
   version + sha256.
2. `gh release create "v<ver>" dist/Driftwall-<ver>.dmg dist/Driftwall-<ver>.zip --title "Driftwall <ver>"`
3. Copy the regenerated `Casks/driftwall.rb` into a checkout of this
   tap repo, commit, and push.

Driftwall is free. If it brightens your desktop: <https://ko-fi.com/ets3d>
