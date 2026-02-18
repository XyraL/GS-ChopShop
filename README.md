# 🏴 GS-ChopShop  
### Premium Syndicate Chop System (Qbox Ready)

---

## Overview

GS-ChopShop is a fully modular chop system built for:

- Solo players
- Groups / Syndicates
- Competitive progression
- Arcade-fast mechanical gameplay

This version focuses on:

- ⚙️ Mechanical-feel chopping (fast but tactile)
- 🏛 Prestige ladder progression
- 🧨 Optional Black Market war mode
- 🛡 Performance hardened systems
- 🚫 No territories
- 🚫 No alliance politics

---

# 🔧 Regular Contracts (Primary Gameplay)

Regular contracts are the core experience.

Each contract includes:

- Vehicle retrieval
- Bay delivery
- Mechanical part removal
- Bonus objectives
- Payout breakdown

---

## ⚙️ Mechanical Chop System (Arcade-Mechanical)

Each part removal:

- ⏱ **2–3 seconds total**
- 🎯 **Quick skill check**
- 🔊 **Tool-specific audio**
- ✨ **Sparks / smoke / debris feedback**
- 🎥 **Subtle camera bump**

---

### Minigame Types (Randomized Per Part)

1. **Bolt Timing**
   - Press in green zone.
2. **Torque Hold**
   - Hold + release in sweet spot.
3. **Rapid Loosen**
   - Quick tap sequence.

Minigames are randomized per part.

---

### Slight Upgrade Advantage

Syndicate speed bonuses slightly:

- Widen success zones
- Reduce fail impact
- Improve overall part speed

Skill still matters.

---

# 🧰 Tool Profiles (Automatic)

Different part types feel different:

| Part Type | Tool Feel |
|---|---|
| Doors / Hood | Ratchet |
| Wheels | Impact Gun |
| Engine | Socket Set |
| Frame / Cut | Cutter |
| Final Strip | Heavy Mechanical |

Each profile controls:

- Audio
- FX burst
- Micro camera feedback

---

# 🧠 Tool Mastery (Individual)

Tool Mastery is **personal progression** (not syndicate power creep).

Tools tracked:
- **Wrench** (doors, hood/trunk, plates, VIN)
- **Impact** (wheels)
- **Socket** (engine)
- **Cutter** (cut steps)
- **Final** (final strip)

XP gains (per tool use):
- +1 on successful completion
- +2 on "perfect" feeling events

Levels: **1–5** per tool.

Benefits are intentionally small (roughly **5–7% max**):
- Slightly faster part completion
- Slightly easier minigame difficulty at high levels

This keeps the economy stable while still rewarding grind.

---

# 🎨 Bay Visual Evolution (Cosmetic)

Your active bay visually upgrades as you progress:

- 0–49 total contracts: clean bay
- 50+: scrap pile appears
- 200+: tool bench + oil props
- 500+: rubber/scrap clutter grows

High total mastery adds an extra tool chest.

These props are **client-only cosmetic** and have **no gameplay advantage**.

---

# 🎯 Modifiers (Now Mechanical)

Modifiers change gameplay, not just payout text.

Examples:

- **Reinforced Bolts** → Extra skill tick
- **Rushed Buyer** → Shorter timer, higher payout
- **Clean Extraction** → Fail removes bonus eligibility
- **High Value Parts** → Specific parts pay more

Modifier effects are reflected in payout breakdown.

---

# 💰 Payout Breakdown

At contract completion, the UI shows:

- Base Contract
- Modifier Bonus
- Perfect Bonus
- High Value Bonus
- Total Earned

Transparent and competitive.

---

# 🏛 Syndicate System

Optional group progression system.

Includes:

- Group creation
- Ranks & permissions
- Shared bank
- Prestige ladder
- Permanent bonuses
- Contribution tracking

---

# 👑 Prestige Ladder (Slow Competitive Model)

- **Max Prestige:** 5
- **Prestige triggers at:** Syndicate Level 15

On Prestige:

- Reset level & influence
- Keep a % of bank (scales by prestige)
- Unlock a permanent bonus slot

### Bank Keep %

- Keep = **25% + (5% × newPrestige)**, capped at **45%**

### Permanent Bonus Pool

Pick unique bonuses (no duplicates). Recommended pool:

- +3% payout
- +5% influence gain
- +3% rare contract odds
- -5% operation cooldown
- +3% routing cap

**Max permanent bonuses:** 4

---

# 🧨 Black Market War (Optional)

Prestige III+ only.

- 90-minute event window
- Event-only contracts award points
- Live leaderboard
- Brutal modifier combinations
- Point-based ranking

This can be disabled in config if you want regular contracts only.

---

# 🛡 Performance Hardening

Designed for long-term server stability:

- Leaderboard caching
- Write batching for event points
- Prestige mutex locking
- Server-side permission checks (never trust client)
- DB readiness guard before queries

---

# 🚫 No Territory System

This version intentionally excludes:

- Territory capture
- Map zone control
- Alliances / rivalries

Focused purely on:

**Contracts + Syndicate progression.**

---

# 📁 Folder Structure

```
client/
  main.lua
  mechanics.lua

server/
  main.lua
  db.lua
  blackmarket.lua (optional)
  prestige.lua

shared/
  config.lua
  contracts.lua

ui/
  (NUI assets)
```

---

# ⚙️ Configuration

Edit `shared/config.lua` to adjust:

- Black Market enable/disable
- Mechanical timing & difficulty scaling
- Event rotation timers
- Routing percentage caps
- Prestige requirements

---

# 📦 Installation

1. Drop the resource folder into your server `resources` directory.
2. Ensure dependencies load first:
   - `oxmysql`
   - `qbx_core` (or your framework)
3. Add to `server.cfg`:

```
ensure GS-ChopShop
```

4. Restart server.

---

# 🧠 Troubleshooting

### DB nil / script errors
If you see:

- `attempt to index a nil value (global 'DB')`

It means `server/db.lua` did not load. Check console for the first parsing error above it.

### “Table doesn’t exist” (oxmysql)
This means migrations didn’t run or the resource started too early.

Make sure `oxmysql` is ensured before GS-ChopShop and restart.

---

# Final Notes

GS-ChopShop is designed to:

- Be fast
- Be competitive
- Be skill-based
- Feel mechanical
- Scale long-term

Not political. Not bloated. Not territory-driven.
