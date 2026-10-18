# GenP — Educational Study Copy

**This repository exists for educational purposes only.**

It is a personal learning project: a readability **split** of an existing AutoIt
program (the "GenP" family), reorganised and annotated so I can study how a
non-trivial AutoIt GUI application is structured — its event loop, module layout,
Windows API usage, and build pipeline.

## Purpose

- Learn the **AutoIt** language and GUI patterns by reading real code.
- Practise **reorganising and documenting** an existing codebase for readability.
- Understand concepts like file patching, registry/firewall/hosts manipulation, and
  code-signing checks *at a conceptual level*.

The goal is **reading and understanding**, not improving, extending, or distributing
any licensing-bypass behavior.

## What this is not

- Not an official release, and not affiliated with the original authors, Adobe, or
  Microsoft.
- Not a tool I endorse using. Nothing here is a recommendation to bypass software
  licensing or terms of service.
- Not a distribution channel — the compiled output is for local study only.

## Disclaimer

This code is provided **as-is, for study only**, with no warranty of any kind. Using
software in ways that violate its license or your local laws is your own
responsibility. The author of these notes takes no responsibility for how anyone else
uses this material.

## Repository layout

| Path | What it is |
|------|------------|
| `main.au3` | Entry point: startup + the main event loop. |
| `src\` | Feature modules the split organises the code into. |
| `origs\` | The untouched original source, kept as a reference/backup. |
| `notes\` | My study notes — see below. |

## Notes

The real documentation lives in `notes\`:

- [`notes\GenP-Notes.md`](notes/GenP-Notes.md) — how this project fits together.
- [`notes\GenP-Features.md`](notes/GenP-Features.md) — the program's tabs and buttons.
- [`notes\AutoIt-Notes.md`](notes/AutoIt-Notes.md) — AutoIt language concepts.

## Known Issues

1. Host upon search runs multiple times. It's due to the loop and search, but I'm too lazy to fix this.

## Working Versions

Tested with 8 - ccx_removed.exe
- Lightroom Classic 15.5.1 (Login required)
- Acrobat 26.1 (Login required)
- Photoshop 27.11 (Logout required)
- Illustrator 30.8.2 (Logout required)
- After Effects 26.5 (Logout required)
- CCX-10.15.0
- Creative Cloud 6.11.0.478.6

NOTE: Lightroom CC will never work despite the version!

## Steps to recreate

1. Logout of Creative Cloud
2. Search & patch all files
3. Enable Firewall for everything but Lightroom Classic
4. Remove AGS + Dummy AGS
6. Login to Creative Cloud
7. Launch LRC
8. Add Firewall to LRC
