# GenP Project Notes

Notes on *this specific codebase* and the reorganization we did, so future-you can
pick it back up. For language concepts, see `AutoIt-Notes.md`.

## Contents

- [TL;DR](#tldr)
- **A. Orientation**
  - [What this project is](#what-this-project-is)
  - [GenP is mostly an orchestrator](#genp-is-mostly-an-orchestrator)
  - [Which source this is built from](#which-source-this-is-built-from)
  - [Glossary / key terms](#glossary--key-terms)
  - [Safety net](#safety-net)
- **B. Structure**
  - [File layout](#file-layout)
  - [Module reference](#module-reference)
  - [How it runs (entry -> inward)](#how-it-runs-entry---inward)
  - [main.au3 in three parts](#mainau3-in-three-parts)
  - [The event loop as a map (button -> module)](#the-event-loop-as-a-map-button---module)
- **C. How features work**
  - [config.ini is the program's data](#configini-is-the-programs-data)
  - [Feature rundown](#feature-rundown)
  - [Why packed files must be unpacked before patching](#why-packed-files-must-be-unpacked-before-patching-upx)
- **D. Known things / discoveries**
  - [Self-hash trailer / "unofficial" warning](#self-hash-trailer--not-from-official-sources-warning)
  - [Why the stamp is weak security](#why-the-stamp-is-weak-security-checksum-vs-signature)
  - [Disguised function names](#disguised-function-names)
  - [Obfuscated strings (Caesar +10)](#obfuscated-strings-caesar-10)
  - ["Declarations" that run code](#declarations-that-run-code)
  - [Bundled binaries and verification](#bundled-binaries-and-verification)
  - [The WinTrust feature lowers system security](#the-wintrust-feature-lowers-system-security-what-it-changes)
- **E. Building & running**
  - [Building it](#building-it)
  - [Official build pipeline (origs\build.ps1)](#official-build-pipeline-origsbuildps1)
- **F. Project log**
  - [What we changed, and how it was verified](#what-we-changed-and-how-it-was-verified)
  - [Deferred (not done)](#deferred-not-done)
  - [Open questions / not yet understood](#open-questions--not-yet-understood)
- **G. Learning modifications (feature removals)**
  - [Lessons from removing a feature](#lessons-from-removing-a-feature)

---

## TL;DR

- **What:** an AutoIt GUI tool (the "GenP" family) that patches installed Adobe apps
  to bypass licensing, plus side-tools (firewall, hosts, proxy, WinTrust/DevOverride).
- **Source:** our working copy is a readability **split** of the developer source
  `origs\GenP-v4.2.1.au3` (225 functions, standard library kept external).
- **Structure:** `main.au3` is the entry/orchestrator; it calls out to feature
  modules in `src\`. The standard library is referenced, not inlined.
- **How it runs:** enter `main.au3` -> startup + load `config.ini` -> `MainGui()`
  builds the window -> a `While/WEnd` loop dispatches each click to a `src\` function.
- **Build:** compile `main.au3` with Aut2exe (`build.ps1`); needs 9 `FileInstall`
  resource files present.
- **One gotcha:** a self-built exe shows a cosmetic *"unofficial source"* warning
  (it's missing the official self-hash stamp). Harmless; see section D.

Scope of this work: **reading the code to learn AutoIt, and reorganizing it for
readability.** Not improving or extending the licensing-bypass behavior.

---

# A. Orientation

## What this project is

An AutoIt GUI program (the "GenP" family) that patches installed Adobe apps so they
run without a valid license, plus side tools for firewall rules, hosts-file blocking,
a local proxy, and Windows signature-check (WinTrust/DevOverride) registry changes.

## GenP is mostly an orchestrator

GenP's own AutoIt code is the **GUI + coordination layer**. Much of the actual work is
**delegated to external programs and tools** that GenP bundles (via `FileInstall`) or
calls, and configures through environment variables / command lines. So a lot of "the
work" lives *outside* the `.au3` source:

| External helper | Kind / language | Job | How GenP drives it |
|-----------------|-----------------|-----|--------------------|
| `mitmdump.exe` (mitmproxy) | bundled **Python** binary | intercept Adobe licensing traffic | bundled + run (Proxy feature) |
| `main.exe` (Older Versions Downloader, MP7909) | separate binary, **likely bundled Python** | download old Adobe installers | bundled + launched in a console; configured via `GENP_INSTALL_DIR` / `GENP_DOWNLOADS_DIR` env vars |
| `UpdateHostsFile.ps1`, `RemoveGudeLogs.ps1` | **PowerShell** | scheduled-task work | bundled + registered as scheduled tasks |
| `wintrust.dll` | patched **DLL** | signature-check bypass | bundled + placed |
| `schtasks`, `certutil`, `netsh`, `ipconfig`, `upx.exe` | Windows CLI / tools | tasks, certs, proxy, DNS, unpacking | `Run` / `RunWait` |

Why this shape: AutoIt is strong for a Windows **GUI and automation glue**, weak for things
like an HTTPS proxy or a complex downloader — so those are purpose-built programs in other
languages, and GenP just orchestrates them. (This is also why removing the Proxy / OVD
features dropped big *binaries* but little *code* — see
[`AutoIt-Notes.md` → Payload size ≠ code size].) When hunting for "where does X actually
happen?", check the `Run`/`RunWait`/`FileInstall` calls, not only the `.au3` functions.

## Which source this is built from

The working copy is a **split of the developer source** `origs\GenP-v4.2.1.au3`:

- It uses the real AutoIt standard library via `#include <Array.au3>` (26 standard
  includes) — the library is **not** inlined.
- 225 app functions, already indented, no comments.

(`origs\GenP-v4.0.4.au3` is an older version, kept for reference only.)

## Glossary / key terms

Short, practical definitions of the jargon this codebase uses:

- **GenP** — the tool itself (an Adobe app patcher / licensing-bypass family).
- **NGL** — Adobe's "Next Generation Licensing" component. The licensing binaries
  (e.g. `adobe_licensing_wf.exe`) the firewall feature targets; see
  `$g_aNGLRelativePaths`.
- **AGS** — Adobe Genuine Service (Adobe's genuine-validation service). The tool can
  remove it or install a "dummy" in its place (`RemoveAGS`, `InstallAGSDummy`).
- **WinTrust** — the Windows component (`wintrust.dll`) that verifies code
  signatures. Related to the `EnableCertPaddingCheck` registry values.
- **DevOverride** — Windows registry switches (IFEO / SideBySide `DevOverrideEnable`)
  that affect how DLLs are allowed to load.
- **UXP** — Adobe's "Unified Extensibility Platform" component (`_PatchAdobeUXPComponent`,
  `_UXPPatchedState`).
- **mitmproxy** — a local HTTPS-intercepting proxy the Proxy feature sets up.
- **Au3Stripper** — AutoIt's obfuscator/optimizer (renames symbols, strips). Run by
  the official build; source of the `#Au3Stripper_Ignore_*` directives.
- **Self-hash trailer** — an 80-byte authenticity stamp the official build appends to
  the exe (`GENP_SELFHASH_01` + SHA-256). See section D.
- **Deloader / Caesar +10** — the shift-cipher used to store some strings obfuscated.

## Safety net

`origs\GenP-v4.2.1.au3` is the **exact, untouched source** this split was produced
from. So the working copy can be regenerated from the source at any time — the source
is the backup.

---

# B. Structure

## File layout

```
test\
  main.au3            top-level code: 26 standard #includes + globals + startup + message loop
  src\
    Config.au3   (12) config.ini + patch-state handling
    Ui.au3       (53) GUI build (MainGui), listview, log, options UI, WM_ handlers
    AdobeApps.au3(31) discovering / launching Adobe apps, toolbar, CC processes
    Patch.au3    (34) the file-patching engine + license-cache logic
    Firewall.au3 (21) NGL firewall rules, AGS
    Hosts.au3    (20) hosts-file / DNS blocking, auto-update task
    Proxy.au3    (26) mitmproxy integration
    DevOverride.au3(21) DevOverride regs, WinTrust, trust/untrust EXEs
    Util.au3      (7) leftovers
  origs\              UNTOUCHED pristine source (GenP-v4.2.1.au3, GenP-v4.0.4.au3) + build.ps1
  notes\              these notes (AutoIt-Notes.md, GenP-Notes.md)
  build.ps1           our compile script (raw Aut2exe)
```

Numbers in () are the function counts (225 total). The `src\` grouping is
best-effort/approximate — AutoIt doesn't care which file a function lives in, so a
function may sit in a slightly odd module. That's cosmetic.

Note: there is **no `include\` folder / StdLib.au3** in this build. The standard
library is referenced externally through the `#include <...>` lines, which AutoIt
resolves from its own install (`C:\Program Files (x86)\AutoIt3\Include`).

## Module reference

Each `src\` file and a few of its most useful functions (names are real; the grouping
is approximate):

| Module | Job | Key functions |
|--------|-----|---------------|
| `Config.au3` | Load/validate `config.ini`, patch-state bookkeeping, **and the self-integrity check** | `_ConfigHealthProblem`, `_ConfigCountProblems`, `SaveOptionsToConfig`, `_InitializeFontLayoutEngine` (integrity check) |
| `Ui.au3` | Builds the window and all UI helpers | `MainGui`, `FillListViewWithFiles`, `MemoWrite`/`LogWrite`, `WM_COMMAND`/`WM_NOTIFY`, `_GetCpTranslation` (string decoder), `_PrecacheDisplayAssets` (welcome window) |
| `AdobeApps.au3` | Find/launch Adobe apps, app toolbar, stop CC processes | `_DiscoverAdobeApps`, `_LaunchApp`, `_BuildAppsToolbar`, `_StopAllAdobeProcesses` |
| `Patch.au3` | The patch engine + restore + license caches | `MyGlobalPatternSearch`, `MyGlobalPatternPatch`, `_PatchLargeFileWithPatterns`, `RestoreFile` |
| `Firewall.au3` | NGL firewall rules + AGS | `CreateFirewallRules`, `RemoveFirewallRules`, `_EnableNGLFirewallRules`, `RemoveAGS`/`InstallAGSDummy` |
| `Hosts.au3` | hosts-file blocking + scheduled auto-update | `UpdateHostsFile`, `RemoveHostsEntries`, `EditHosts`, `_SetupHostsAutoUpdate` |
| `Proxy.au3` | mitmproxy setup/run + Windows proxy toggle | `_SetupMitmproxy`, `_StartMitmproxy`/`_StopMitmproxy`, `_EnableWindowsProxy` |
| `DevOverride.au3` | DevOverride regs, WinTrust, trust/untrust exes, UPX | `AddDevOverride`/`RemoveDevOverride`, `ManageWinTrust`, `TrustEXEs`/`UntrustEXEs`, `IsUPXPacked` |
| `Util.au3` | Leftovers | `Deloader` (string decoder), `_Exit`, `OpenWF` |

## How it runs (entry -> inward)

1. You run/compile **`main.au3`**. AutoIt pastes in all `#include`s — first the 26
   standard `<...>` libraries at the top, then the `src\` modules at the bottom —
   and registers every function.
2. Top-level code in `main.au3` runs top to bottom:
   - **Header + startup**: directives (`#NoTrayIcon`, `#RequireAdmin`), the standard
     includes, global declarations, single-instance guard (`_Singleton`), ensure
     `config.ini` exists (`FileInstall`), load settings via `IniRead`, resolve the
     Adobe / WinTrust folder paths, load target-file and pattern lists, check for
     the hidden `-updatehosts` command-line mode.
   - `GUIRegisterMsg(...)` then **`MainGui()`** -> jumps into `src\Ui.au3`, builds
     the whole window, and fills in all the `$idBtn...` control-ID globals.
   - `While 1 ... WEnd` event loop.
3. The loop is a **dispatch table**: `GUIGetMsg()` returns the clicked control's
   ID, a `Select`/`Case` matches it, and the handler usually calls a function in
   one of the `src\` modules, then returns to the loop.

`main.au3` is the hub; `src\` (and the standard library) are spokes it calls into
and returns from. The `src\` files never start on their own.

## main.au3 in three parts

1. **Header + startup** — directives, the 26 standard `#include <...>` lines, global
   declarations, and the startup logic. Order matters here: many "declarations" are
   actually `IniRead` calls that execute in place, so config must be loaded before
   the settings that depend on it.
2. **Build + event loop** — `MainGui()` then `While 1 ... WEnd` (the main body).
3. **Module includes** — the `#include "src\..."` lines at the bottom; definitions
   only, nothing "runs" when reached. They're last so the global declarations above
   are seen first (avoids "used before declaration" warnings).

## The event loop as a map (button -> module)

| Button / area | Handled in |
|---------------|------------|
| Search, Patch (Cure), Restore, Modified | logic inline in `main.au3`, calling `src\Patch.au3` |
| Window / list / log / options UI | `src\Ui.au3`, `src\Config.au3` |
| Firewall tab | `src\Firewall.au3` |
| Hosts tab | `src\Hosts.au3` |
| Proxy tab | `src\Proxy.au3` |
| WinTrust / DevOverride | `src\DevOverride.au3` |
| Finding / launching Adobe apps | `src\AdobeApps.au3` |

The big handlers (Search, Patch, Restore, Save Options, Proxy) are written inline
in the loop; the many small ones are 1-3 lines.

---

# C. How features work

## config.ini is the program's data

Startup mostly *reads* `config.ini`:
- `[Info] ConfigVer` — config version (compared to program version).
- `[Options]` — user settings -> `$b...` flag variables.
- `[TargetFiles]` — the list of file names Search looks for.
- `[CustomPatterns]` — per-file entries used by the patch step.

It also *writes* a couple of keys on launch and validates version + per-section
entry counts (`_ConfigHealthProblem`, `_ConfigCountProblems`). The actual work
happens later in the event-loop handlers, which act on what startup loaded.

## Feature rundown

High-level, "what it does + where", one line each:

- **Search** — scans the Adobe install folder for the `[TargetFiles]` names
  (`RecursiveFileSearch`) and lists what it finds.
- **Patch (Cure)** — for each checked file, applies byte-patterns from the config
  (`MyGlobalPatternSearch` / `MyGlobalPatternPatch`), keeping a `.bak` backup.
- **Restore** — puts the `.bak` backups back (`RestoreFile`), undoing a patch.
- **Firewall** — creates Windows Firewall rules to block the NGL licensing binaries
  from the network (`CreateFirewallRules`, `_EnableNGLFirewallRules`).
- **Hosts** — adds Adobe activation domains to the Windows hosts file
  (`UpdateHostsFile`); can install a scheduled task to refresh them.
- **Proxy** — sets up a local mitmproxy to intercept Adobe licensing traffic
  (`_SetupMitmproxy`, `_StartMitmproxy`).
- **WinTrust / DevOverride** — registry/DLL changes so patched binaries pass Windows
  signature checks / load (`ManageWinTrust`, `AddDevOverride`).

## Why packed files must be unpacked before patching (UPX)

The Patch engine works by **byte-pattern search-and-replace** (`MyGlobalPatternSearch` /
`MyGlobalPatternPatch`) using the patterns in `config.ini`. That only works on a file's
**real, readable code**. A **UPX-compressed** file has its code compressed/scrambled, so
patching it *as-is* goes wrong one of two ways:

- The target byte-patterns **aren't present** in the packed bytes → the patch **finds
  nothing and silently does nothing** → that app is left *un-bypassed*. The tool's core
  goal (license bypass) **quietly fails** for that file, with no obvious error. **Or**
- Blindly rewriting bytes inside a compressed blob would **corrupt the packed file** →
  a broken app.

So for any packed file, `upx -d` **must** run *before* patching — via
`_AutoUnpackIfRuntimeInstaller` (which calls `IsUPXPacked` → `PatchUPXHeader` → `upx -d`).
It's a **hard prerequisite**, not an optional nicety: skip it and patching either no-ops or
corrupts.

Scope keeps it from being "core": only a narrow category is packed (the "runtime installer"
files), and GenP detects each file by the `UPX!` byte marker, so most files never need it.
But **for the files that *are* packed, unpacking is mandatory** — it's the line between
"license bypass works" and "patch quietly failed / app broken." That's why UPX is a small
but **non-droppable** helper: rarely used, yet essential wherever it applies.

---

# D. Known things / discoveries

Running log of non-obvious findings. Each: what it is, where, why it's non-obvious.

## Self-hash trailer / "not from official sources" warning

If you compile with plain Aut2exe (our `build.ps1`) and run it, a **"System Notice"**
dialog appears: *"You did not obtain this version from official sources, we can't
guarantee that it is safe to use."* This is GenP's **own authenticity check**, not
anything from Adobe. How it works:

- `_InitializeFontLayoutEngine()` in `src\Config.au3` (a deliberately misleading
  name — it's the integrity check) reads the program's **own compiled .exe**
  (`@AutoItExe`) and looks at the **last 80 bytes** for a trailer: a 16-byte magic
  marker `GENP_SELFHASH_01` + a 64-char SHA-256 hash.
- It computes SHA-256 of the exe **minus that trailer** and compares to the stored
  hash. Match -> `$bTrustVerified = True`.
- If not verified, it calls `_RenderTextMetricBuffer()` (another fake name) which
  shows the warning dialog.

Why self-builds warn: the **official build script appends that 80-byte trailer as a
separate post-compile step** (it prints "Appending self-hash trailer..."). Plain
Aut2exe does not, so our exe is unstamped -> check fails -> warning. It is purely a
build-pipeline difference; **the code split does not cause it** (same source through
the same pipeline gives the same result).

## Why the stamp is weak security (checksum vs signature)

The stamp is the *only* thing the warning checks, and it is **not secure against
anyone who reads the code**. It is a plain `SHA-256(body)` with **no secret key**:
anything doing the stamping is fully in the open, so anyone can hash any (modified)
exe and write that hash onto the end — it will then verify as "official." It is a
**checksum, not a signature.**

- Real code signing uses **asymmetric crypto**: the author signs with a *private
  key* they never ship; verification uses the *public key*. Unforgeable even if you
  read all the code.
- This check has no key, so it only catches the easy cases: accidental corruption
  (truncated download), lazy tampering (edited exe, not re-stamped), and casual users.
- Takeaway: **a keyless self-hash is tamper-evidence, not authentication.** It can
  say "this changed," never "this came from who it claims." Proving authorship always
  needs a secret the verifier does not have.

## Disguised function names

In this (originally obfuscated) source, **don't trust function names** — several do
something unrelated to what they're called:

| Name | What it actually does | Where |
|------|----------------------|-------|
| `_InitializeFontLayoutEngine` | self-integrity check (the self-hash verify) | `src\Config.au3` |
| `_RenderTextMetricBuffer` | shows the "unofficial source" warning dialog | `src\Ui.au3` |
| `_GetCpTranslation` | Caesar-cipher string decoder | `src\Ui.au3` |
| `_PrecacheDisplayAssets` | the welcome/about window (+ sets a trust-display flag) | `src\Ui.au3` |
| `Deloader` | string de-obfuscator (same shift cipher) | `src\Util.au3` |

## Obfuscated strings (Caesar +10)

Some strings are stored shifted by +10 in the printable ASCII range (wrapping), and
decoded at runtime — which is why plaintext search can't find them. `_GetCpTranslation()`
holds the warning/welcome strings; `Deloader()` decodes `$g_aSignature` into a URL.
It's a trivial, keyless cipher (a speed bump against casual searching, not security).

## "Declarations" that run code

Watch out in `main.au3`'s startup: lines like
`Global $x = IniRead(...)` **create the variable and execute `IniRead` right then.**
So a block that looks like "just declarations" can be doing real work (reading files),
and the order of those lines matters. (General AutoIt gotcha — see `AutoIt-Notes.md`.)

## Bundled binaries and verification

The exe bundles third-party binaries via `FileInstall` (all now under `resources\`).
Source review shows *how* GenP uses them (the `Run`/`RunWait` calls); their *identity*
needs checking the **bytes**. Verified **2026-10-12** — recorded so future-you can re-check
(a hash change means the file was swapped):

| File | Version (PE metadata) | Size (bytes) | SHA-256 | Notes |
|------|-----------------------|--------------|---------|-------|
| `upx.exe` | UPX 5.0.1 (2025-05-06), The UPX Team | 599,040 | `8def9daba0817636962e60878e117ee1dcba6c3f64fb4bc13449d447385f1b5b` | Presents as genuine UPX 5.0.1 (version resource + official release date both 2025-05-06). Byte-match to an official hash not done — UPX publishes no per-asset digests; VirusTotal the SHA-256 to confirm. MD5 `a14acd4e0fd7f388b6c42cde82fec28b`. |
| `wintrust.dll` | Microsoft WINTRUST.DLL 10.0.19041.630 | 382,712 | `8c6c791e8db8728f9a610def238c61be054bfa3de487bf6ab037130a61a3ef19` | **Patched** Microsoft DLL — invalid signature *by design* (the WinTrust bypass). A scanner (Gridinsoft) shows **0 AV detections**. Size matches GenP's own `DevOverride.au3` check (expected 382,712). MD5 `b7a38368a52ff07d875e6465bd7ee26a`. |

Other `resources\` items are data/scripts, not "run" binaries: `config.ini` (settings
seed, kept at the project root), `RemoveGudeLogs.ps1` (Gude cleanup), `ccx-start-10.8.1.zip`.
Deleted during the feature removals: `mitmdump.exe`, `mitmproxy_genuine_fullguard.py`,
`main.exe` (the OVD).

Re-verify: `(Get-Item file).VersionInfo` (version, no execution) · `Get-FileHash` /
`sha256sum` (bytes) · `virustotal.com/gui/file/<sha-256>` (identity — expect UPX clean;
the patched `wintrust.dll` flagged hacktool/riskware but with no real malware family). This
is the "verify the bytes, not just the source" half — see `AutoIt-Notes.md` → "Security:
AutoIt exes are powerful (and abused)".

## The WinTrust feature lowers system security (what it changes)

The **WinTrust** tab is the most security-relevant feature in GenP. Its job: make
GenP-patched binaries pass Windows **code-signature checks** (patching breaks a file's
signature, so apps that self-verify would pop up / refuse to load). It does this by
**weakening signature verification** — in three pieces, **two of them machine-wide**:

1. **Registry, system-wide (`AddDevOverride`):**
   - `…\Image File Execution Options\DevOverrideEnable = 1` **and**
     `…\SideBySide\DevOverrideEnable = 1` → re-enable `.local` DLL redirection of protected
     DLLs machine-wide (a DLL-sideloading safeguard normally suppressed for manifest'd apps).
   - `…\Cryptography\Wintrust\Config\EnableCertPaddingCheck = 0` (64- **and** 32-bit) → keep
     Windows' **lenient** Authenticode check (CVE-2013-3900) so modified/appended binaries
     still validate as "signed", machine-wide.
2. **Patched `wintrust.dll`, per-app (`TrustEXEs`):** drops a neutered `wintrust.dll` (always
   answers "trusted") into each Adobe app's `<exe>.local\` folder, so that app's signature
   checks always pass. The real `System32\wintrust.dll` is **not** modified.

Why it matters: an always-"trusted" `wintrust.dll` is a real attack primitive, and
`DevOverrideEnable=1` + `EnableCertPaddingCheck=0` are **persistent, machine-wide** reductions
in Windows' code-integrity defenses (they survive reboots). The patched DLL is per-app
(limited blast radius); the registry changes are not. The feature is **optional and
situational** (the patch works without it; only some pro apps need it), so the safe default
is **don't enable it unless you actually get signature popups**.

Reverse with **`RemoveDevOverride`** (`DevOverrideEnable=0`, `EnableCertPaddingCheck=1`) +
**`UntrustEXEs`** (delete the `.local\wintrust.dll` files), or Final Clean Check. General
principle — a dangerous DLL's risk is defined by *where it's loaded* — see `AutoIt-Notes.md`
→ "Security: AutoIt exes are powerful (and abused)".

> **This build:** the apply path is disabled — `AddDevOverride` is neutered (`[WINTRUST-REMOVED]`),
> so GenP can no longer enable the override or place the patched DLL. `RemoveDevOverride` is
> kept intact for cleanup.

---

# E. Building & running

## Building it

Compile **`main.au3`** (the compiler follows includes automatically; never compile
`src\` files separately). Keep `src\` next to `main.au3` — the `"src\..."` include
paths are relative to it. The standard `<...>` includes come from the AutoIt install.

```powershell
& "C:\Program Files (x86)\AutoIt3\Aut2Exe\Aut2exe.exe" /in "main.au3" /out "GenP.exe" /x64
```

Our `build.ps1` does this headless (via `Start-Process`), after checking the resources.

**Build-time resource files (FileInstall):** the build embeds files via `FileInstall`;
each must exist at its path (relative to `main.au3`) or the compile stops at the first
missing one. To get the current list, search all source for `FileInstall(` and take
the first (literal) argument:

```powershell
Select-String -Path "main.au3","src\*.au3" -Pattern 'FileInstall\(\s*"([^"]+)"' -AllMatches |
  ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
```

These resource files were not part of the downloaded `.au3` and must be sourced
separately. Test-run uncompiled: `AutoIt3_x64.exe main.au3` (triggers UAC via
`#RequireAdmin`, needs `config.ini` present).

## Official build pipeline (origs\build.ps1)

`origs\build.ps1` is the GenP authors' real build script (the one whose log shows
"Appending self-hash trailer..."). It expects to sit next to a `GenP\` folder
(source + resources) and a `WinTrust\` folder, and does:

1. **Guards** — requires Administrator; checks execution policy; logs everything to
   `Logs\build.log` via `Start-Transcript`.
2. **Bootstraps tools** — needs AutoIt + SciTE under `C:\GenP-BuildEnv\`; if missing,
   downloads them from autoitscript.com (curl, fallback .NET WebClient) and extracts.
3. **wintrust.dll** — MD5-checks `GenP\wintrust.dll` vs known stock/patched hashes; if
   not already patched, runs `WinTrust\patch_wintrust.ps1` and bundles the result.
4. **Builds** — finds the single `.au3` in `GenP\`, compiles it through
   **AutoIt3Wrapper.au3** (not raw Aut2exe). The wrapper reads `#AutoIt3Wrapper_*`
   directives and runs **Au3Stripper** (the obfuscator) — this is the step that
   produces the stripped/renamed distributed build, and the source of the
   `#Au3Stripper_Ignore_*` directives.
5. **Stamps** — `Append-SelfHashTrailer` appends the 80-byte `GENP_SELFHASH_01` + hash.
6. **Releases** — moves the exe to `Release\` and writes `*.hashes.txt` for exe + source.

How our `build.ps1` differs (and why that's fine for learning):

| Step | Official build.ps1 | Our build.ps1 |
|------|--------------------|---------------|
| Compile | AutoIt3Wrapper + **Au3Stripper obfuscation** | raw Aut2exe (no obfuscation) |
| Dependencies | downloads AutoIt/SciTE if missing | assumes AutoIt installed |
| wintrust.dll | patches + bundles it | uses whatever is placed in the folder |
| Self-hash trailer | **appends it** -> no warning | doesn't -> cosmetic warning |
| Output | `Release\GenP*.exe` + hash files | `GenP.exe` in place |

Net: the official script obfuscates, patches wintrust, and stamps; ours just
compiles. The only visible consequence of ours is the cosmetic "unofficial" warning,
and skipping obfuscation is a plus for reading/learning.

---

# F. Project log

## What we changed, and how it was verified

Built from the developer source `origs\GenP-v4.2.1.au3`:

1. **Split** — moved the 225 app functions into `src\` feature modules; kept all
   top-level code (header, startup, GUI build, message loop) in `main.au3`, with the
   `#include "src\..."` lines added at the bottom. No reformatting was needed (the
   source was already indented), and no StdLib extraction was needed (the library is
   already external).

Verification:
- **Au3Check exit 0** on `main.au3` — identical to the clean source's own baseline;
  all includes resolve, all symbols defined.
- **Line accounting**: 9,551 -> 9,551 code lines, 0 lost or added (only comment
  banners and the `#include "src\..."` lines differ).

## Deferred (not done)

- **Globals extraction** — move the static global declarations out of `main.au3`'s
  header into `src\Globals.au3`. Low risk; pure relocation.
- **Turning big inline event-loop handlers into functions** (e.g. `_OnSearchClick()`),
  so the loop becomes a short table. **Medium risk** — it's a logic rewrite, not a
  move: `ContinueLoop` becomes `Return` + caller checks, and top-level `Local`
  variables that cross between blocks need explicit declaration. Do this only with a
  real run/compile to verify behavior.

## Open questions / not yet understood

Things we haven't dug into yet (edges for future-you):

- **`MainGui()` internals** — exactly what tabs/controls it builds and how the
  `$idBtn...` IDs map to the layout. Not read in detail yet.
- **Patch engine internals** — how `MyGlobalPatternSearch` / `MyGlobalPatternPatch`
  actually match and apply the byte patterns from `[CustomPatterns]`.
- **`$g_aSignature`** — what URL it decodes to (via `Deloader`) and where it's used.
- **Full `config.ini` schema** — all sections and what each controls (we only looked
  at the few startup reads).

---

# G. Learning modifications (feature removals)

The working copy has had features **switched off as learning exercises** (removals, not
improvements) — by commenting, never deleting, each tagged for search. The **inventory**
of what's removed (tags, scope, how to revert, resource side effects) lives in
[`GenP-Features.md` → "Removed in this build"](GenP-Features.md). Captured here are only
the reusable lessons.

## Lessons from removing a feature

1. **A feature is not in one place** — follow its *call graph* across files, not one
   file. A keyword grep can miss a live caller whose name lacks the keyword
   (`_AppendToLogWindow` had no "proxy"/"mitm" in it); sweep by function name.
2. **Three involvement types, handled differently:** *mis-file* (move it — e.g. the
   `_GenP_WM_*` handlers → `Ui.au3`); *genuine dependency* (remove the call, keep the
   callee if shared); *bridge helper* (filed by what it does, used by one feature —
   orphaned when its caller goes, e.g. `_SilentHostsInjector`).
3. **Creation path ≠ cleanup path.** Removing how a feature is *created* doesn't make its
   *cleanup* pointless — a prior build may have left state on the machine. (Kept the Final
   Clean Check hosts-task step for exactly this; see its note in `Patch.au3`.)
4. **No nested functions → orphaned helpers don't vanish** (see `AutoIt-Notes.md`): a
   single-use helper is still a global, so removing its one caller leaves dead code to
   find and wrap by hand.
5. **Naive text scan ≠ compiler.** `build.ps1`'s `FileInstall` pre-check was made
   `#include`-aware so it stops demanding resources for disconnected code.
