# Changelog

What each release changed, for players. The newest release is at the top. Each release's section here becomes its notes on GitHub (see "Releasing" in the README).

## [Unreleased]

### Added
- Survivor picks two starting weapons in the lobby, as in the base game.
- Primal Dread support: the jungle, its enemies, bosses and items play the same for everyone. Everyone has the same holes, map decoration, dig sites and poacher zones, and sees the puddles, mutant and meca enemies, charging dinosaurs, the brachiosaurus and T-rex, lasers, warning lines and jumps, deflected bullets, boomerangs, carbon bow arrows, pet attacks and the slowed enemy time of the time shifter and pocket watch.

### Changed
- Works with Brotato **1.2.0.1** and no longer with 1.1.15.4 (the last release for 1.1.15.4 is 1.12.3). Everyone in a session needs 1.2.0.1.
- The lobby offers only the zones whose DLC you own.
- The host's item sets (main menu) apply to everyone in the session. Characters and starting weapons from a set the host switched off don't show in the lobby.

### Fixed
- Joining failed on 1.2.0.1, and several parts of the mod didn't load.
- Script errors on the end screen.
- Enemies that leave the map without dying (e.g. at its edge) now disappear for every player.
- Poisoned fruit (Abyssal Terrors) now shows up for every player, not only for the host.
- The evil mob now evolves (look, health bar) for every player, and the materials it eats disappear for everyone.

## [1.12.3] - 2026-10-29

### Added
- `tools/lancommander_set_name.ps1`: sets the player name for LAN parties managed with LANCommander.

### Changed
- Lobby: the status line wraps; the bottom row has its buttons left and right.

### Fixed
- Clients no longer fire a second, local volley of alien eyes.

## [1.12.2] - 2026-10-29

### Fixed
- The Join page keeps a game listed for 10 s after its last beacon instead of dropping it at once.

## [1.12.1] - 2026-10-28

### Fixed
- The mod didn't start in the shipped game (Steam/GOG) since 1.12.0.

## [1.12.0] - 2026-10-27

### Added
- Abyssal Terrors DLC support: its enemies, bosses, curses and charm show correctly for every player.

### Fixed
- Several DLC items and characters raised script errors (heal over time after the wave, steps of other players, captain's sword).

## [1.11.0] - 2026-10-26

### Changed
- Last Potato Standing: the storm drifts. Elimination modes never share loot.
- Team Race ends with the wave in which the first team is out.
- The scoreboard greys out dead players.

## [1.10.0] - 2026-10-26

### Changed
- Settings page: grouped rows and one help box. Clients see the host's settings read-only.

## [1.9.0] - 2026-10-26

### Added
- Game modes: a mode setting with seven modes besides co-op (not playtested much yet).
- Loot sharing settings for materials and crates.
- Teams in the lobby, a scoreboard (toggle with Tab or Back), and an end screen player list.

## [1.8.2] - 2026-10-24

### Fixed
- Script errors when a stat change was still pending as the wave ended.

## [1.8.1] - 2026-10-24

### Fixed
- Clients who quit or rejoined while the run ended now see "The run is over".

## [1.8.0] - 2026-10-23

### Added
- Rejoin after a lost connection: the game reconnects into the old slot, back in at the next wave.

## [1.7.0] - 2026-10-21

### Added
- Progress in a session counts on your own save: a won run credits your character; challenges in a wave count for the team; rewards are kept.

### Changed
- Lobby: selected characters and weapons have a fill in the player's colour.

### Fixed
- Jellyshield and weapon swings matched between players.

## [1.6.0] - 2026-10-21

### Added
- Lobby settings page with an enemy scaling preset (Relaxed, Normal, Tough) and the choice time.

### Changed
- Lobby uses the full screen height; only the host has the Settings button.

### Fixed
- Script errors in bullet-hell waves at the highest danger.

## [1.5.0] - 2026-10-21

### Added
- Choice time between waves: a 90 s countdown; at 0, random upgrades are picked and Go is pressed.

### Fixed
- The left stick works for the local player in a session.

## [1.4.0] - 2026-10-20

### Fixed
- Bullets, other players' movement and deaths look right on every machine (stop events, smoother remote players).

## [1.3.1] - 2026-10-19

### Fixed
- Smoother enemies and players over WiFi.

## [1.3.0] - 2026-10-19

### Changed
- Better balance beyond 7 players: the enemy count stops at a cap, the rest becomes enemy HP.
- Better performance with many enemies.

## [1.2.0] - 2026-10-18

### Added
- Random potato names as default player names, unique in the lobby.

### Fixed
- Everyone is un-ready when the host returns to the lobby after a run.

## [1.1.0] - 2026-10-18

### Added
- End screen: a dropdown shows any player's stats, weapons and items.

## [1.0.0] - 2026-10-18

### Added
- First release: LAN multiplayer for up to 12 players, one per PC. Host or join from the main menu (discovered games or by IP), a lobby with characters, weapons and ready-up, a larger arena and more enemies as more players join, and upgrades and shop on each machine between waves.

[Unreleased]: https://github.com/Moolt/brotato-lan-coop/compare/v1.12.3...HEAD
[1.12.3]: https://github.com/Moolt/brotato-lan-coop/compare/v1.12.2...v1.12.3
[1.12.2]: https://github.com/Moolt/brotato-lan-coop/compare/v1.12.1...v1.12.2
[1.12.1]: https://github.com/Moolt/brotato-lan-coop/compare/v1.12.0...v1.12.1
[1.12.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.10.0...v1.11.0
[1.10.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.8.2...v1.9.0
[1.8.2]: https://github.com/Moolt/brotato-lan-coop/compare/v1.8.1...v1.8.2
[1.8.1]: https://github.com/Moolt/brotato-lan-coop/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/Moolt/brotato-lan-coop/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/Moolt/brotato-lan-coop/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Moolt/brotato-lan-coop/releases/tag/v1.0.0
