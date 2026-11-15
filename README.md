# Dopewars for the Breakpoint 2026 badge

*Dope Wars* for the Solana Breakpoint 2026 badge: a Lua app for the App Store
built into Solana OS. Also available on Android and the App Store.

Thirty days, twelve drugs, six Tube stations around London for Breakpoint
2026, a loan shark, three cops.

## Files

| File | Role |
|---|---|
| `main.lua` | Splash, screens, input and game flow |
| `lib/game.lua` | Rules, no UI |
| `lib/texts.lua` | Every string shown on screen |
| `app.json` | App Store manifest |
| `tools/smoke_test.py` | Headless test against a stub of the badge API |

## Screens and controls

The market is the main screen, under a header with the station, the day, cash,
debt and bank. Everything else opens as a sheet in place of the market list.

| Where | Keys |
|---|---|
| Market | up / down: pick a drug. select: trade it. left: menu (the station's services, instructions, give up). right: move, or finish on the last day. back: leave the app |
| Trade | left / right: quantity (hold for steps of 10). up / down: buy, sell. select: confirm |
| Amount (debt, bank) | left / right: pick a digit. up / down: change it. select: confirm. Starts on the maximum |
| Menus | up / down, select, back |
| Text | select: next page. left: previous page |

The game is saved on the market screen, after every move and after every
round of a fight, so leaving the app loses nothing.

## Test

```
pip install lupa
python3 tools/smoke_test.py
```

Then on the real thing: open <https://solana.com/breakpoint/badge/apps/submit>,
drop a zip of `main.lua`, `app.json` and `lib/`, and use *Try in emulator* or
*Run on badge*.
