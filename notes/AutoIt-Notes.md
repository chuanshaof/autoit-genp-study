# AutoIt Notes

Conceptual notes on the AutoIt language, collected while reading this project.
These are the things that trip up newcomers, especially people coming from
Python/JS/C.

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

## GUI model

- **Build phase:** create controls (`GUICtrlCreateButton`, `...Checkbox`,
  `...ListView`, ...). Each returns a numeric **control ID** you store.
- **Message loop:** `While 1 ... WEnd` calling `GUIGetMsg()`, which returns the
  ID of whatever was clicked (or a special constant like `$GUI_EVENT_CLOSE`, or
  `0` if nothing happened). A `Select`/`Case` (or `Switch`) then dispatches to the
  matching handler. The loop does not block, so periodic/polling work can sit at
  the top of it.
- `GUIRegisterMsg($WM_..., "FuncName")` registers a lower-level Windows-message
  callback used alongside the loop.

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
