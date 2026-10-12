# AutoIt Notes

Conceptual notes on the AutoIt language, collected while reading this project.
These are the things that trip up newcomers, especially people coming from
Python/JS/C.

## Contents

- **Language basics**
  - [What AutoIt is](#what-autoit-is)
  - [Blocks need explicit terminators](#blocks-need-explicit-terminators)
  - [Operators that bite](#operators-that-bite)
  - [Variables and scope](#variables-and-scope)
  - ["Declarations" can run code](#declarations-can-run-code)
  - [Arrays](#arrays)
  - [No classes or modules](#no-classes-or-modules)
  - [Error handling: check `@error` immediately](#error-handling-check-error-immediately)
- **Program structure**
  - [The standard library (UDFs) and `#include`](#the-standard-library-udfs-and-include)
  - [How a multi-file script runs (the two phases)](#how-a-multi-file-script-runs-the-two-phases)
  - [No nested functions](#no-nested-functions)
  - [AutoIt as glue (shelling out)](#autoit-as-glue-shelling-out)
- **GUI**
  - [GUI model](#gui-model)
    - [The basic building block: one control = one line](#the-basic-building-block-one-control--one-line)
    - [How it differs from web/DOM](#how-it-differs-from-webdom-important-if-you-know-web-dev)
    - [How a control "belongs to" the window](#how-a-control-belongs-to-the-window-the-implicit-current-target)
    - [Tabs are visibility tags, not containers](#tabs-are-visibility-tags-not-containers)
    - [Build invisibly, then reveal in one shot](#build-invisibly-then-reveal-in-one-shot)
    - [Dummy controls: an ID with no appearance](#dummy-controls-an-id-with-no-appearance)
    - [The message loop (how clicks become actions)](#the-message-loop-how-clicks-become-actions)
- **Build & tooling**
  - [FileInstall: files embedded at compile time](#fileinstall-files-embedded-at-compile-time)
  - [Tooling](#tooling)
  - [Security: AutoIt exes are powerful (and abused)](#security-autoit-exes-are-powerful-and-abused)

---

## What AutoIt is

- A Windows scripting language, originally for GUI automation, now a general
  scripting/GUI language. One `.au3` source file (plus any it includes) either
  runs under the interpreter (`AutoIt3.exe`) or compiles to a standalone `.exe`.
- Not whitespace-sensitive. Indentation is purely cosmetic (unlike Python).

## Blocks need explicit terminators

There are no braces. Every block is opened and closed by keyword:

| Open | Close |
|------|-------|
| `Func` | `EndFunc` |
| `If ... Then` (multi-line) | `EndIf` |
| `For` / `While` / `Do` | `Next` / `WEnd` / `Until` |
| `Switch` / `Select` | `EndSwitch` / `EndSelect` |
| `With` | `EndWith` |

- One-line form needs no terminator: `If $x Then DoThing()`.
- Multi-line `If` **must** end its first line with `Then`.
- Because indentation is ignored, a missing `EndIf` won't be caught by eye — run
  the checker (see Tooling).

## Operators that bite

- `=` is **both** assignment and equality (`$x = 5` assigns; `If $x = 5` compares).
- `==` is **case-sensitive string** equality.
- `<>` is "not equal".
- **String concatenation is `&`, not `+`.** `+` does math and will silently
  misbehave on strings.
- Boolean logic is the words `And` / `Or` / `Not` — not `&&` / `||` / `!`.
- Ternary exists: `$x = ($cond) ? 1 : 0`.

## Variables and scope

- Every variable starts with `$`: `$count`. Macros start with `@`: `@CRLF`,
  `@ScriptDir`, `@error`, `@ProgramFilesDir`, `@WindowsDir`, `@AppDataCommonDir`,
  `@TempDir`.
- **Path macros are resolved at *runtime*, on the machine running the exe** — not
  baked in at compile time. So `@AppDataCommonDir` becomes *that* PC's common
  AppData (normally `C:\ProgramData`), `@TempDir` *that* user's temp folder, etc.
  This is why a constant like `@AppDataCommonDir & "\GenP\mitmproxy"` is portable:
  it recomputes the correct location per machine on each launch. Also note
  assigning such a constant is **pure string-building with no disk side effect** —
  it defines a path; it does not create the folder.
- Declare with `Global` (whole script), `Local` (inside a function),
  `Const` (can't change), `Enum` (auto-numbered constants).
- **No block scope.** A `Local` declared inside an `If` lives for the whole
  function.
- **At the top level, `Local` behaves exactly like `Global`.** You'll see
  top-level `Local $x = ...` — it's effectively a global.
- Variables are untyped (variants); the same variable can hold a string, number,
  or array.

## "Declarations" can run code

A declaration and a function call can be the same line:

```autoit
Global $bFindACC = IniRead($sINIPath, "Options", "FindACC", "1")
```

This creates the variable **and** executes `IniRead` right then. So a block that
looks like "just declarations" may actually be doing work (reading files, etc.),
and the order of those lines matters.

## Arrays

- **0-based.** Fixed size; grow with `ReDim` (slow in loops) or `_ArrayAdd`.
- `UBound($a)` = element count; `UBound($a, 2)` = number of columns of a 2D array.
- Declare with size: `Global $a[0][5]` (0 rows, 5 cols — empty, filled later).
- Literal init only at declaration: `Local $a[3] = [1, 2, 3]`.

## No classes or modules

- AutoIt has no objects/classes of its own and no module system. Shared state
  between functions is normally done with **global variables**.
- For a hashmap/dictionary, code borrows a Windows COM object:
  `ObjCreate("Scripting.Dictionary")`.
- A common cheap "set" trick: build a string like `"|a|b|c|"` and test membership
  with `StringInStr($s, "|" & $item & "|")`.

## Error handling: check `@error` immediately

There is no try/catch. Many functions signal failure by setting the `@error`
macro (and sometimes `@extended`). Check it on the **very next line**, because
almost any following operation resets it:

```autoit
$result = SomeCall()
If @error Then ...   ; must be checked here
```

`SetError(n, ext, ret)` is how a function sets `@error`.

## The standard library (UDFs) and `#include`

- AutoIt ships a standard library of "User-Defined Functions" (UDFs), written in
  AutoIt itself, in the install's `Include\` folder: `Array.au3`, `GuiListView.au3`,
  `WinAPI.au3`, `Crypt.au3`, etc.
- You pull them in with `#include <Array.au3>` and just call the functions.
  Library function names start with `_` (e.g. `_ArrayAdd`); internal helpers
  start with `__`.
- Look functions up in the official docs (autoitscript.com -> Function Reference)
  rather than reading their source.

## How a multi-file script runs (the two phases)

1. **Include expansion + function registration (before anything runs).**
   AutoIt starts at the file you run/compile and textually pastes in every
   `#include`, recursively, producing one conceptual big file. Every `Func`
   definition from every file is registered, so functions are callable regardless
   of which file they're in or what order they appear.
2. **Execution.** AutoIt runs the **top-level statements** top to bottom,
   **skipping `Func` definitions**.

Consequences:
- Function definition **position doesn't matter** (you can `#include` the files
  holding them at the bottom).
- Top-level statement **order does matter** (they run in sequence).
- So: move functions freely between files safely; be careful moving top-level
  code.

## No nested functions

Every `Func ... EndFunc` is **top-level**; you cannot define a function inside another
(no Python/JS-style inner functions or closures). So a helper used by only one function
is still a separate global function.

Consequences when refactoring:
- Removing a function does **not** remove its private helpers — they stay as orphaned
  global functions (dead code) you must find and remove by hand. With inner functions
  they'd vanish with the parent.
- There's no language-level "private to this function" signal — only the **call graph**
  tells you a helper is used in just one place. (Use a function-name search for every
  caller; don't trust naming or file location.)

## AutoIt as glue (shelling out)

AutoIt is often used as a **coordination layer**, not the place heavy work happens. It's
great for a Windows GUI + automation, and it delegates the rest to other programs. Two
idioms to recognise:

- **`Run` / `RunWait` a separate program or Windows CLI tool** (`schtasks`, `certutil`,
  `powershell`, a bundled `.exe`) and let *it* do the job. `RunWait` blocks until it
  finishes; `Run` fires and continues.
- **Configure a child process via environment variables:** `EnvSet(...)` *before* `Run(...)`,
  and the child inherits them (a child process inherits the parent's environment). This is
  how you hand settings to a program you didn't write and have no API into — no shared
  memory, no function calls, just inherited env vars (and the child's working directory,
  which is `Run`'s 2nd argument).

Consequence: **"where's the logic?" may be another process in another language**, reached
by a one-line `Run`. When tracing behaviour, follow the `Run`/`RunWait` calls (and any
`FileInstall`'d `.exe`/`.ps1`), not just the `.au3` functions.

## GUI model

### The basic building block: one control = one line

A **control** is any single visible thing: a button, checkbox, text box, label.
You make one by calling a `GUICtrlCreate...` function, which also returns a numeric
**control ID** you store so you can refer back to it later:

```autoit
$idBtnCure = GUICtrlCreateButton("Patch", 251, 520, 94, 32)
;            ^make a button        ^label  ^x   ^y  ^w  ^h
```

The four numbers are **absolute position + size in pixels** (x from left, y from
top, width, height). The returned ID (`$idBtnCure`) is like a deli ticket number:
it's how every other part of the program says "this button" — both to **configure
it** and to **listen for clicks on it** (see the message loop below).

Shorthand: passing **`-1`** as the control ID to a follow-up call means "the control
I just created", so you don't repeat the variable:

```autoit
GUICtrlSetState(-1, $GUI_DISABLE)   ; disable the button we just made
```

### How it differs from web/DOM (important if you know web dev)

There is **one outer box — the window** (`GUICreate(...)`), like the browser window
/ `<body>`. But unlike the DOM:

- **No nesting tree.** Every control is a **direct child of the one window**; there
  are no container boxes holding children.
- **No auto-layout.** There is no flow/flex/grid. You hand-place **every** control
  at absolute x/y pixels. The web equivalent is `position:absolute` on *everything*,
  all siblings of `<body>`.
- **Nothing reflows.** Move or remove one control and its neighbors don't shift —
  each is pinned to its own pixels. (This is why GUI-build code is long and tedious:
  someone placed every pixel by hand.)

### How a control "belongs to" the window: the implicit "current" target

You never wire a control to a parent (no `appendChild`). Instead AutoIt keeps an
invisible pointer to **"the window/tab I'm currently adding to"**:

- `GUICreate(...)` makes a window **and sets it as current**.
- Every later `GUICtrlCreate...` auto-attaches to **whatever is current**.

### Tabs are visibility tags, not containers

A tabbed window uses the same "current" trick. `GUICtrlCreateTabItem("Main")` opens
a tab (now current); controls made after it get **tagged** "show only on Main";
`GUICtrlCreateTabItem("")` closes the set. The controls are **still flat children of
the window at absolute coords** — switching tabs just hides one tag-set and shows
another. It's visibility-switching, not DOM-style containment.

### Build invisibly, then reveal in one shot

Every `GUICtrlCreate...` builds into the window **while it's hidden**. A single call:

```autoit
GUISetState(@SW_SHOW)
```

is what finally draws the finished window on screen — so the user never sees a
half-built UI flicker into place.

### Dummy controls: an ID with no appearance

`GUICtrlCreateDummy()` makes a control with **no visible form** but a real ID. It's
a placeholder so the event loop can still reference an `$id...` (and have a `Case`
for it) even when there's no actual button — common for removed/unsurfaced features.

### The message loop (how clicks become actions)

- **Build phase:** all the `GUICtrlCreate...` calls above (typically wrapped in a
  `MainGui()`-style function), ending with `GUISetState(@SW_SHOW)`.
- **Message loop:** `While 1 ... WEnd` calling `GUIGetMsg()`, which returns the
  ID of whatever was clicked (or a special constant like `$GUI_EVENT_CLOSE`, or
  `0` if nothing happened). A `Select`/`Case` (or `Switch`) then dispatches to the
  matching handler. This is the other half of the IDs: build phase **creates** each
  `$idBtn...`; the loop **reacts** to it. The loop does not block, so periodic/
  polling work can sit at the top of it.
- `GUIRegisterMsg($WM_..., "FuncName")` registers a lower-level Windows-message
  callback used alongside the loop (e.g. `WM_NOTIFY` for listview checkbox clicks).

## FileInstall: files embedded at compile time

`FileInstall("source", "dest")` embeds `source` into the compiled `.exe` at build
time, to be written to `dest` at run time. The **source must be a literal string**
(the compiler has to find it while building). To find a script's build-time
resource dependencies, search for every `FileInstall(` and take the first
argument.

Two-phase, and usually **lazy**: the bytes ride *inside* the exe from build time,
but extraction to disk only happens when that `FileInstall` line actually executes.
The common pattern guards it so it runs on demand, not at launch:

```autoit
If Not FileExists($g_sMITM_EXE) Then FileInstall("resources\...\mitmdump.exe", $g_sMITM_EXE, 1)
```

So a bundled resource for a feature the user never touches never lands on their
disk, even though it's always carried in the exe. (The `1` third arg = overwrite.)

### Payload size ≠ code size

The compiled `.exe` = the (small) compiled script **plus every `FileInstall` source
embedded whole**. So a feature's weight in the exe is dominated by what it *bundles*,
not how much code it has:

- A feature with little code but a big bundled binary balloons the exe. (GenP's Proxy
  feature is ~660 lines of script but `FileInstall`s `mitmdump.exe` — a standalone
  Python+mitmproxy binary of tens of MB — so it added that whole payload to the exe.)
- A pure-code feature adds almost nothing to the exe, however complex. (Removing the
  Hosts "Schedule updates" button changed the output by ~a kilobyte of bytecode.)

Consequence: **removing a feature reclaims space only if it bundled resources.**
Disconnect a module whose `#include` is commented out and its `FileInstall` lines stop
compiling, so the bundled bytes are dropped from the exe — that, not the deleted code,
is what shrinks it. To gauge a feature's exe footprint, look at its `FileInstall`
sources' file sizes, not its line count.

## Tooling

- **Au3Check** (`Au3Check.exe`): the compiler's front-end / validator. It expands
  all includes and resolves all symbols. Exit 0 + no warnings = structurally
  sound. Use after every edit.
- **Tidy**: the official formatter (indentation, spacing). SciTE has it built in.
- **Aut2exe** (`Aut2Exe\Aut2exe.exe`): compiles `.au3` -> `.exe`.
  `Aut2exe /in main.au3 /out App.exe /x64`.
- **Run uncompiled** for testing: `AutoIt3_x64.exe main.au3`.
- Directives like `#RequireAdmin` (relaunch elevated / UAC) and `#NoTrayIcon`
  are compile/run directives starting with `#`.
- `#Au3Stripper_*` directives are hints for Au3Stripper (an obfuscator/optimizer),
  not part of normal running.

## Security: AutoIt exes are powerful (and abused)

Something to be aware of when reading/running AutoIt tools. It follows from the "glue"
nature: `FileInstall` can bundle *any* file into the exe, and `Run`/`RunWait`/
`ShellExecute` can launch *anything* — with the user's privileges (and `#RequireAdmin`
means full admin).

**Capability ≠ vulnerability — two different things:**

- **AutoIt is a known malware-authoring favorite.** `FileInstall` (pack a payload) +
  `Run` (execute it) + trivial syntax make it low-effort to weaponise, so AV engines are
  suspicious of AutoIt-compiled exes (false positives are common). But this is *ease of
  abuse*, not a unique power — any compiled language (C, Go, PyInstaller, Electron) can
  bundle and run arbitrary code too. "Can run anything" = native code with user rights,
  not AutoIt specifically.
- **The `Run`-anything capability is not, by itself, an external attack surface.** An
  outsider can't inject new `Run` calls into a running script; they'd have to modify the
  exe/source first — and if they can do that, you're already compromised in any language.
  The real vectors are **trojaned copies** (a tampered build with extra `Run`/`FileInstall`
  lines) and **downloaded payloads** (anything the script fetches and then acts on).

**The end-user risk (the sharp one):** a compiled `.exe` is **opaque** — unlike a `.ps1`
or `.py` you can read first, you must trust the author blind. Add `#RequireAdmin` (runs
with full privileges) and an **untrusted source** (forums, mirrors), and you have the
classic Windows malware delivery vector: **cracks / keygens / "patchers."** A large share
of real infections arrive exactly this way — "it's just a patcher," clicked through a UAC
prompt. Obfuscation (Au3Stripper, the cipher/base64 tricks) makes it *worse* to audit, not
better. And note: a plain Aut2exe build is trivially **decompilable** back to source, so
the exe hides little from a determined reader but everything from a casual one.

**Auditing an AutoIt tool's "reach outside itself":** grep for `Run`, `RunWait`,
`ShellExecute`, `ShellExecuteWait`, and `FileInstall`. Those few calls are the entire
external-execution surface — check what each one launches/bundles.

**Defenses are process, not code:** read the source instead of trusting the exe; run
untrusted admin tools in a **VM / sandbox**; treat *opaque + admin + untrusted-source* as a
red flag by default. (A keyless self-hash "official source" check — like GenP's — is
tamper-*evidence* at best, and forgeable, so not real assurance.)
