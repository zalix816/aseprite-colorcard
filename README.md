# 🎨 ColorCard — Game Style Color Palettes for Aseprite

An Aseprite extension with a built-in **game-style color database**. Pick colors for any material — characters, trees, terrain, metal, buildings — already split into **six shading roles**: **Outline / Shade / Base / Light / Highlight / Shadow**.

Built for pixel artists who struggle with color: instead of guessing how dark a shadow should be, click the pre-computed swatch.

> 🌐 **Browse the whole database in your browser**: open [preview.html](preview.html) — same data, zero install.

## ✨ Features

- **5 art styles** × **15 games** × **281 items**, each with 6 shading roles
- **Style presets**: Western (WoW-like) · GBA Retro · HD-2D Modern (Octopath-style) · Vivid Cartoon (Stardew-like) · Dark Dungeon
- **Cascade filters**: Style → Game → Category → Subcat → Type
- **Click a swatch** → sets the foreground color **and** copies the HEX
- **Load Palette** → writes the whole game's palette (up to 256 colors) into the current sprite
- **Copy All HEX** → copies every visible item's six-role colors as text
- Pure Lua + JSON data — **add your own styles/games by dropping in a JSON file**, no code changes

## 📦 Install

1. Download [`ColorCard-v1.2.6-en.aseprite-extension`](ColorCard-v1.2.6-en.aseprite-extension) from this repo (or from Releases)
2. Double-click it, or in Aseprite: **Edit → Preferences → Extensions → Add Extension**
3. Restart Aseprite
4. Open via **View → ColorCard**

Requires **Aseprite 1.3.6 or newer** (tested on 1.3.6; on 1.3.10+ clipboard copy is native, older versions fall back to the system clipboard tool).

## 🔌 Usage

```
Style [dropdown]   Game [dropdown]
Category [dropdown]  Subcat [dropdown]  Type [dropdown]
Item
      Outline  Shade  Base  Light  Highlight  Shadow
Grass   ■      ■      ■     ■      ■          ■
...     (click any swatch = set FG color + copy HEX)
```

- **‹ / ›** pages through items (12 per page)
- **Load Palette** writes the current game's colors into the sprite palette

## 🗂 Data structure

Data lives in `extension/data/palettes/*.json` — one file per style:

```json
{
  "id": "stardew",
  "name": "Vivid Cartoon",
  "desc": "...",
  "games": [
    {
      "id": "stardew", "name": "Stardew Valley", "source": "...",
      "entries": [
        {
          "cat1": "Environment", "cat2": "Grassland", "cat3": "Lawn", "name": "Lawn",
          "colors": { "outline": "#2E4A1E", "shade": "#2F7A10", "base": "#56B509",
                      "light": "#8BD31E", "highlight": "#C4EC55", "shadow": "#2A4A33" }
        }
      ]
    }
  ]
}
```

Drop a new JSON into the palettes folder and it appears in the extension automatically.

## 🔍 Where the colors come from

Base colors are anchored on real, sourced palettes — then expanded into the six roles with hue-shift shading rules (cool-shifted shadows, warm-shifted highlights, unified outline hue):

| Style | Games | Source |
|---|---|---|
| GBA Retro | Pokémon Ruby/Sapphire · Soul Knight · Fire Emblem · Generic | Official Pokémon RSE exterior tileset palette (pret decomp, via Lospec) · Endesga 32 |
| HD-2D Modern | Octopath Traveler · Triangle Strategy · Generic | Style analysis of the games' dual-range palettes · DB32 |
| Vivid Cartoon | Stardew Valley · Terraria · Generic | Sampled colors (grass `#58ac14/#44a318/#328530`, hardwood `#824925`, wheat `#ffe600`) · biome conventions |
| Dark Dungeon | Darkest Dungeon · Dead Cells · Generic | DD wiki sampled colors (`#3c3b40`, `#660011`, `#bdc241`…) · Dead Cells art blog (analogous outdoors / complementary indoors) |
| Western | World of Warcraft (56 items) · Generic | Author's category template, colors derived per keyword |

Classic palettes referenced: PICO-8 · GameBoy · DB16 / DB32 · Endesga 32.

## 🛠 Extending

- **Add a game**: copy an existing JSON block inside a style file, change `id`/`name`, add entries
- **Add a style**: add another JSON file — it shows up as a new tab
- **Tune colors**: edit the HEX values directly; the extension reads the folder on every panel open

## 📄 License

MIT — see [LICENSE](LICENSE). Game names referenced for stylistic research only; all trademarks belong to their owners.
