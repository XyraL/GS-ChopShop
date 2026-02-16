# GS-ChopShop (QBOX) – Black Market Tablet

A modern, cinematic chop shop system with a tablet UI, smart modifiers, bonus objectives, upgrades, reputation, and optional co-op splits.

## Features
- **Tiered contracts** (T1/T2/T3) with progress + reputation tracking
- **Smarter contracts** via **modifiers** (payout/alert/radius/time)
- **Bonus objectives** per contract (cash + rep)
- **Special Contracts** (rep-gated) with stronger payout + extra modifiers
- **Upgrades** (speed, payout, heat, scanner, dispatch)
- **Leaderboard + history**
- **Operator Alias profile** (leaderboard uses aliases, not real names)
- **Co-op invite** (invite nearest player; partner receives a payout/rep cut)
- Cinematic UI micro-animations + SFX hooks

## Commands
- `/choptest` (admin/debug if enabled in config)
- `/chopaccept` / `/chopdecline` (fallback co-op accept/decline)

## Config Notes
- `config.lua` is the primary config.
- Legacy blocks are still supported but now have clearer aliases:
  - `Config.RealismSteps` (alias of `Config.V2`)
  - `Config.ShellPipeline` (alias of `Config.V3`)

## Database
Tables:
- `gs_chopshop_stats`
- `gs_chopshop_history`
- `gs_chopshop_progress`
- `gs_chopshop_upgrades`
- `gs_chopshop_profiles` (alias/privacy)

## Co-op
- Leader invites nearest player from the tablet (Active Contract panel).
- Partner gets a split defined in `Config.Coop.partnerShare`.

## Troubleshooting
- If you see NUI background artifacts (black box), ensure `--shadow:none;` and **no** `-webkit-mask` in `web/style.css`.
