# GenP Features — the actual tabs & buttons

What GenP looks like **as a program you use** — every tab in the window and what each
button does. This is the user-facing map (not the source code); for the code behind it
see [`GenP-Functions.md`](GenP-Functions.md) and [`GenP-Notes.md`](GenP-Notes.md).

The window is a single fixed-size dialog with **8 tabs** across the top. Every tab has a
"GenP Wiki && Guides" link at the bottom.

```
┌───────────────────────────────────────────────────────────┐
│  Main │ Options │ WinTrust │ Hosts │ Proxy │ Firewall │ AGS │ Log │
└───────────────────────────────────────────────────────────┘
```

Built in [`src/Ui.au3` → `MainGui()`](Ui.au3#L65).

---

## 1. Main

The home screen — find Adobe files, patch them, undo. A big checkbox **list** of found
app files (grouped by app, with a Status column: Patched / Unchanged / etc.), two
progress bars, and two rows of buttons.

**Selection row (above the list):**

| Button | Does |
|--------|------|
| Uncheck All | Uncheck every file in the list. |
| Check All | Check every file. |
| Unpatched | Check only files not yet patched. |
| Patched | Check only files already patched. |
| Refresh | Re-scan / re-verify the current list. |

**Action row (bottom):**

| Button | Does |
|--------|------|
| **Path** | Point GenP at a custom folder to scan/patch instead of the default Adobe folder. |
| **Search** | Scan the Adobe install folder(s) for patchable files and fill the list. (Turns into **Stop** while running.) |
| **Patch** | The main action — patch every checked file (keeps a `.bak` backup of each). |
| **Modified** | Re-scan and show only files that still differ from baseline, i.e. what *still needs* patching. |
| **Restore** | Undo patches on checked files by putting their `.bak` backups back. |

---

## 2. Options

Settings. **Nothing here takes effect until you click Save Options** (a red reminder
appears when something is unsaved). Grouped into boxes:

**First Run Options**
- *Create and populate new patch_states.ini* — build the patch-state ledger from scratch (uses the Path location).
- *Reconcile imported patch_states.ini against current files* — match an imported ledger to what's actually installed.

**Scan Options**
- *Always search for ACC* — also scan the Adobe Creative Cloud common folder.
- *Search in default named folders only* — restrict scanning to standard Adobe folder names (faster).
- *Use custom default search path* — scan a folder you choose (shown beneath the checkbox) instead of `Program Files\Adobe`.

**Patch Options**
- *Show Beta apps* — include Adobe Beta apps in results.
- *Enable Good patch* — apply the "good" pattern variant.
- *Show app launch toolbar* — show the floating quick-launch bar for patched apps.
- *Older versions download* — enable older-version download behavior.
- *Clear license caches after patching* — wipe Adobe license caches when a patch finishes.
- *Enable NGL Firewall rule* — auto-apply the NGL network-block rule as part of patching.

**Hosts Options**
- *Hosts List URL* — the blocklist URL the Hosts tab pulls from (editable).
- *Trigger one-off capture and launch on save* — one-shot: start a capture and launch an app when you save.

**Clean Options**
- *Reset patch_states.ini* — wipe the patch-state ledger on save.
- *Final Adobe Clean Check* — run a final cleanup sweep.

**Save Options** — commit the above to `config.ini`.

---

## 3. WinTrust

Make patched binaries pass Windows' signature / DLL checks so they stop throwing popups.
*(Credit to Team V.R.)*

| Button | Does |
|--------|------|
| Toggle WinTrust | Turn the WinTrust certificate-check bypass on/off. |
| Toggle Reg Key | Turn the DevOverride registry key on/off. |
| Set Trust Path | Choose which folder these changes apply to (shown as "Path: …"). |

---

## 4. Hosts

Block Adobe activation/telemetry domains via the Windows hosts file, to cut down popups.

| Button | Does |
|--------|------|
| Update hosts | Download the blocklist (from the Hosts List URL) and write it into the hosts file. |
| Edit hosts | Open the hosts file to edit it manually. |
| Clean hosts | Remove GenP's blocklist entries (enabled only if they're present). |
| Restore hosts | Restore the `hosts.bak` backup (enabled only if a backup exists). |
| Schedule updates | Install a scheduled task that refreshes the blocklist automatically. |

---

## 5. Proxy

Run a local **mitmproxy** that intercepts and neutralises Adobe "heartbeat" licensing
traffic. *(Credit to MP7909.)* A live **Status:** line shows the current state. Buttons
unlock in order as setup progresses.

| Button | Does |
|--------|------|
| Setup | Install mitmproxy and trust its certificate. |
| Targeting | Choose Global, or specific apps, to route through the proxy. |
| Start / Stop Proxy | Run or stop the proxy. |
| Open Log | Open the live proxy activity log window. |
| Remove | Uninstall mitmproxy and clean everything up. |

---

## 6. Firewall

Block Adobe apps from the internet using **Windows Defender Firewall** rules (another way
to reduce popups). Manages Defender only — third-party firewalls need manual setup.

| Button | Does |
|--------|------|
| Add Rules | Create outbound block rules for the Adobe/NGL binaries. |
| Toggle Rules | Enable or disable the existing rules (enabled once rules exist). |
| Remove Rules | Delete GenP's firewall rules (enabled once rules exist). |
| Open Windows Firewall | Open `wf.msc` (the Windows Firewall console). |

---

## 7. AGS (Adobe Genuine Service)

Stop "Adobe Genuine Service Alert" popups by dealing with the AGS components.

| Button | Does |
|--------|------|
| Remove AGS | Remove the AGS components outright. |
| Dummy AGS | Replace AGS with harmless dummy files so nothing runs in the background. |
| Restore AGS | Remove all dummies and restore the originals (enabled only if backups exist). |

---

## 8. Log

A read-only **Activity Log** of everything GenP did this session (starts with the GenP
and Config versions).

| Button | Does |
|--------|------|
| Copy | Copy the whole log to the clipboard. |

---

## Not a tab: the floating launch toolbar

If *Show app launch toolbar* is on (Options tab), a small separate always-handy bar shows
buttons to launch your patched Adobe apps directly. It has its own minimise and config
buttons. Built in [`src/AdobeApps.au3` → `_BuildAppsToolbar()`](AdobeApps.au3#L730).
