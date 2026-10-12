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

> **This working copy has features switched off (learning exercises).** The tab strip
> above is GenP's *full* layout; in this build the **Proxy** tab is gone (7 tabs) and the
> Hosts **Schedule updates** button is gone. Removed items are flagged **[REMOVED]** inline
> below; the full inventory + how to revert is in
> ["Removed in this build"](#removed-in-this-build-learning-exercises) at the end.

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
- *Enable Good patch* — applies the stronger "good" pattern variant, which also **blocks Adobe's licensing network calls** (keeps apps activated without phoning home). Side effect: Adobe's own licensing component then keeps failing and writing `gude-*.log` files that pile up in Adobe folders — so enabling this on Save prompts you to set up **Gude Log Cleanup** (see below) to auto-delete them.
- *Show app launch toolbar* — show the floating quick-launch bar for patched apps.
- *Older versions download* — **[REMOVED — `[OVD-REMOVED]`]** enable older-version download behavior. *(Launched the bundled `main.exe` downloader.)*
- *Clear license caches after patching* — wipe Adobe license caches when a patch finishes.
- *Enable NGL Firewall rule* — auto-apply the NGL network-block rule as part of patching.

**Hosts Options**
- *Hosts List URL* — the blocklist URL the Hosts tab pulls from (editable).
- *Trigger one-off capture and launch on save* — **[REMOVED — `[PROXY-REMOVED]`]** one-shot: start a capture and launch an app when you save. *(Was part of the Proxy feature.)*

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
| ~~Schedule updates~~ **[REMOVED — `[SCHEDULE-HOSTS-REMOVED]`]** | Install a scheduled task that refreshes the blocklist automatically. |

---

## 5. Proxy  — **[REMOVED in this build — `[PROXY-REMOVED]`]**

> This entire tab and feature are switched off in this working copy (see
> ["Removed in this build"](#removed-in-this-build-learning-exercises)). The description
> below documents what it does in a *full* GenP build.

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

### The whole feature is optional (and self-contained)

`mitmdump.exe` and its Python script are **embedded inside `GenP.exe` at build time**
(via `FileInstall`). They are **not written to disk until you use the feature** — they
sit dormant inside the exe otherwise.

- The **only** thing that unpacks them is the **Setup** button
  ([`_SetupMitmproxy`](../src/Proxy.au3#L58)), which `FileInstall`s them to
  `%ProgramData%\GenP\mitmproxy\`. If you never click Setup, mitmdump never touches your
  disk, never runs, and no certificate is installed.
- **Remove** (or the Final Adobe Clean Check, below) deletes those files again, so the
  machine goes back to having nothing on disk.

### It's not only driven from this tab

All the mitmdump launch/stop logic lives in `src\Proxy.au3`, but it's reached from a few
places — worth knowing so a reference to it elsewhere isn't mistaken for an unrelated
feature:

| Entry point | Tab | Effect on mitmdump |
|-------------|-----|--------------------|
| Setup / Targeting / Start-Stop / Open Log / Remove | **Proxy** | the five buttons above (Setup is the only one that unpacks). |
| "Trigger one-off capture and launch on save" checkbox | **Options** | **Starts** the proxy for a single capture session, then unchecks itself. Requires Setup to have been run first — it does *not* unpack on its own. |
| "Final Adobe Clean Check" | **Options** | **Tears it down** — stops the proxy, removes the cert, deletes the files (same as Remove). |
| "Add to Hosts" button in the proxy log window | **Proxy** (log window) | **Stops** the proxy first (a domain can't be blackholed in the hosts file while the proxy is still intercepting it), then writes the hosts entry. |
| Startup | — | read-only check only, to enable/disable the Proxy buttons at launch. |

So mitmdump is **never used unless you go through one of these**, and it only ever runs
after an explicit **Setup**.

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

## Not a tab: Gude Log Cleanup (prompted)

Not a button — GenP **offers it automatically** when you turn on **Enable Good patch** and
click Save Options. Because the Good patch blocks Adobe's licensing calls, Adobe's own
software keeps failing and writing `gude-YYYY-MM-DD.log` files into Adobe folders, which
pile up over time. If you accept the prompt, GenP installs a **scheduled task** ("GenP Gude
Log Cleanup") that periodically runs `RemoveGudeLogs.ps1` to delete those logs (on the
drives you pick). Turning the Good patch back off later prompts to remove the task.

- **What it cleans:** `gude*.log` files under `AppData\Roaming\Adobe`, `ProgramData\Adobe`,
  and `<drive>:\Adobe`. Pure housekeeping — it only deletes those logs and records what it
  removed; no network, nothing else touched.
- **How it runs:** the same pattern as any GenP scheduled task — `schtasks` registers a task
  that runs `powershell.exe -File RemoveGudeLogs.ps1`. (The `.ps1` is one of the bundled
  `FileInstall` resources in `resources\`.)
- **Why the logs exist:** GenP doesn't create them — Adobe's licensing component does, each
  time the patch blocks its phone-home. GenP just sweeps them up.

Built in [`src/Hosts.au3` → `_SetupGudeCleanup` / `_ShowGudeSetupPrompt`](Hosts.au3).

---

## Removed in this build (learning exercises)

This working copy has features **switched off** to study how a feature threads through the
code. Nothing is deleted — everything is commented and tagged, so one search finds every
piece and reverts it.

| Tag (search the source) | Removed | Where |
|-------------------------|---------|-------|
| `[PROXY-REMOVED]` | the whole **Proxy** tab + feature (mitmproxy), incl. the Options *trigger-capture* checkbox | `main.au3`, `Ui.au3`, `Patch.au3`, `Hosts.au3`, `Proxy.au3` (module disconnected), `build.ps1` |
| `[SCHEDULE-HOSTS-REMOVED]` | the Hosts tab's **Schedule updates** button + its dialog | `Ui.au3`, `main.au3`, `Hosts.au3` |
| `[OVD-REMOVED]` | the Options **Older versions download** feature (bundled `main.exe` downloader) | `Ui.au3`, `main.au3`; `resources\mitmproxy\main.exe` deleted |

**Mechanics:** multi-line blocks use AutoIt `#cs … #ce`; single lines use `;`. To revert
a feature: search its tag, delete the `#cs`/`#ce` marker lines, and re-enable any
`;`-commented line or `#include`. The three `_GenP_WM_*` handlers were *moved* (from
`Proxy.au3` into `Ui.au3`) because they are main-window handlers, not proxy — that move is
permanent and stays on revert.

**Resource side effect:** all three files under `resources\mitmproxy\` are now gone —
`mitmdump.exe` + `mitmproxy_genuine_fullguard.py` (Proxy) and `main.exe` (the Older
Versions Downloader) — since none is embedded any more. The folder is empty. Because
those `FileInstall`s now sit inside `#cs … #ce` blocks (or a disconnected module),
`build.ps1`'s pre-check was made comment-/`#include`-aware so it no longer demands them.

**Still live on purpose:** the **Final Adobe Clean Check** still removes a hosts-update
scheduled task if one exists (a prior/official build could have installed one) — removing
the *button* that creates it doesn't make the *cleanup* pointless. (The proxy teardown in
that same check *was* removed, but only because its function lived in the excised
`Proxy.au3`.)

For the *why*/lessons behind these removals, see [`GenP-Notes.md` → section G](GenP-Notes.md).
