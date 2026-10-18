# Brotato LAN Coop

A [Brotato](https://store.steampowered.com/app/1942280/Brotato/) mod that adds LAN multiplayer: up to 12 players, one per PC.

**Status:** early development. See [docs/lan-coop-plan.md](docs/lan-coop-plan.md) for the plan and milestones.

## Requirements

- Brotato **1.1.15.4**. You need to own the game; this repo contains no game files.
- ModLoader 6.3.0 (bundled with Brotato)

## Install

1. Download `Moolt-Lan_Coop.zip` from the [latest release](https://github.com/Moolt/brotato-lan-coop/releases/latest), or build it yourself with `./build.sh` (creates `dist/Moolt-Lan_Coop.zip`).
2. Copy the zip into the `mods/` folder next to the Brotato executable (create the folder if it doesn't exist).
3. Start the game.

## Development

The mod is developed against a local decompiled copy of the game, which is not part of this repo:

```
brotato-multiplayer/
├── Decompiled/          # decompiled Brotato project, opened in a Godot 3.x editor
│   ├── mods-unpacked/Moolt-Lan_Coop -> ../../brotato-lan-coop/mods-unpacked/Moolt-Lan_Coop
│   ├── CLAUDE.md -> ../brotato-lan-coop/CLAUDE.md
│   └── docs      -> ../brotato-lan-coop/docs
└── brotato-lan-coop/    # this repo
```

Create the symlinks from inside `Decompiled/`:

```bash
ln -s ../../brotato-lan-coop/mods-unpacked/Moolt-Lan_Coop mods-unpacked/Moolt-Lan_Coop
ln -s ../brotato-lan-coop/CLAUDE.md CLAUDE.md
ln -s ../brotato-lan-coop/docs docs
```

### Releasing

1. Bump `version_number` in `mods-unpacked/Moolt-Lan_Coop/manifest.json` and commit.
2. Tag and push: `git tag v1.0.0 && git push origin v1.0.0` (the tag must match the manifest version).

The `Release` workflow builds the zip and publishes a GitHub release with it attached. The `Build` workflow also builds the zip on every push to `master` and on pull requests; it is downloadable from the run's Artifacts section.

## License

[MIT](LICENSE). Brotato itself belongs to Blobfish; this license covers only the code in this repo.
