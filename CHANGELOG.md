# Enhanced Battleground Scoreboard — Changelog

## 1.1
- Added support for non-CoA icons (i.e. default wotlk ones) for other 3.3.0-3.3.5a realms that are not Conquest of Azeroth, like Bronzebeard, or even non-Ascension
- Made an audit and hardened against API changes

## 1.2

- Class icons now display correctly on non-English clients — icons are matched by locale-independent class token instead of the localized class name.
- Added icons for the Conquest of Azeroth classes whose internal token differs from their display name: Bloodmage, Venomancer, Primalist, Templar, Runemaster, Knight of Xoroth, and Felsworn.
- Fixed icons occasionally appearing as raw `|TInterface\GLUES\...` text before the class atlas finished loading; the textures are now preloaded and kept resident.
- Icon atlas and level cap are auto-detected (Conquest of Azeroth vs. standard WotLK) and reconfirmed from live scoreboard data, so the level is hidden at the correct max level (60 on CoA, otherwise the client's cap).
- New command `/ebs classtokens` lists every class token the client knows and flags any that have no icon art.
- Robustness: media paths derive from the addon folder name (survive a rename), plus safer color, level, and cache handling.
