# Spell Rank Display

A World of Warcraft addon that shows the spell rank number on the default
action bar buttons, so you can tell multiple ranks of the same spell apart.

Put Lesser Heal rank 1 and rank 2 side by side and they normally look
identical. With this addon, each button shows a small **1** or **2**. Ranks
lower than the highest one your character knows are shown in a different
color (red by default), so outdated ranks stand out after you visit a trainer.

It works with the standard Blizzard action bars. It doesn't replace them or
change how they work; it only draws a number on top.

## Compatibility

Made for **World of Warcraft Forever**.

## Installation

1. Download this repository (**Code → Download ZIP**) and extract it.
2. Copy the `SpellRankDisplay` folder into your AddOns folder, for example:
   `World of Warcraft\_forever_\Interface\AddOns\SpellRankDisplay`
3. Restart the game, or type `/reload` if you're already logged in.

## Settings

Open **Esc → Options → AddOns → Spell Rank Display**, or type `/srd`.
Changes apply immediately and are shown in a live preview.

| Setting | Options |
|---|---|
| Position | Any corner, the middle of any edge, or the center |
| Padding | 0–10, distance from the edge of the button |
| Font | Fonts that ship with the game |
| Font size | 8–24 |
| Outline | None, Outline, Thick outline |
| Shadow | On or off |
| Colors | One color for lower ranks, one for the highest known rank |
| Show on highest rank | Hide the number when a button already has your best rank |

Settings are saved per account. **Reset to defaults** restores the original
look.

## Notes

- Macros show a rank too, when the game can tell which spell the macro casts,
  for example `/cast Lesser Heal(Rank 1)`. Macros that switch spells with a
  modifier key update as you press it.
- Only the default Blizzard action bars are supported. Bars from other addons,
  such as Bartender or Dominos, won't show ranks.

## Author

Rackham
