# build.ps1 - compile main.au3 to an .exe, with pre-flight checks.
# Usage:
#   .\build.ps1            # check resources + syntax, then compile (x64)
#   .\build.ps1 -x86       # compile 32-bit instead
#   .\build.ps1 -Force     # compile even if some FileInstall resources are missing
#                          # (the compile will FAIL on the first missing one - this
#                          #  just skips the friendly pre-check)
param([switch]$x86, [switch]$Force)

$ErrorActionPreference = "Stop"
$root   = $PSScriptRoot
$aut2exe = "C:\Program Files (x86)\AutoIt3\Aut2Exe\Aut2exe.exe"
$au3chk  = "C:\Program Files (x86)\AutoIt3\Au3Check.exe"
$main    = Join-Path $root "main.au3"
$outExe  = Join-Path $root "GenP.exe"

if (-not (Test-Path $main))    { throw "main.au3 not found in $root" }
if (-not (Test-Path $aut2exe)) { throw "Aut2exe.exe not found - is AutoIt installed?" }

# --- 1) list the FileInstall resources the build embeds, and check they exist ---
Write-Host "== FileInstall resources (needed at COMPILE time) ==" -ForegroundColor Cyan
# Only scan files the build actually uses: main.au3 + its UNCOMMENTED
# #include "src\..." lines. This mirrors what the compiler sees, so an excised
# module (its #include commented out, e.g. [PROXY-REMOVED]) no longer triggers
# false "missing resource" errors for FileInstall lines sitting in dead code.
$scanFiles = @("$root\main.au3")
Select-String -Path "$root\main.au3" -Pattern '^\s*#include\s+"([^"]+)"' -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $scanFiles += (Join-Path $root $_.Groups[1].Value) }
$deps = Select-String -Path $scanFiles -Pattern 'FileInstall\(\s*"([^"]+)"' -AllMatches |
        ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$missing = @()
foreach ($d in $deps) {
    $path = Join-Path $root $d
    $ok = Test-Path $path
    if (-not $ok) { $missing += $d }
    "{0}  {1}" -f ($(if($ok){"[ok]  "}else{"[MISS]"})), $d
}

if ($missing.Count -gt 0 -and -not $Force) {
    Write-Host "`n$($missing.Count) resource file(s) missing. Put them at these paths (relative to main.au3):" -ForegroundColor Yellow
    $missing | ForEach-Object { "   $root\$_" }
    Write-Host "`nThen re-run. (Or comment out the matching FileInstall line in the source" -ForegroundColor Yellow
    Write-Host " if you don't need that feature, or run '.\build.ps1 -Force' to try anyway.)" -ForegroundColor Yellow
    return
}

# --- 2) syntax check (informational) ---
Write-Host "`n== Au3Check ==" -ForegroundColor Cyan
& $au3chk -q $main
Write-Host "Au3Check exit code: $LASTEXITCODE  (0 = clean; non-zero usually means warnings)"

# --- 3) compile ---
Write-Host "`n== Compiling ==" -ForegroundColor Cyan
if (Test-Path $outExe) { Remove-Item $outExe -Force }
$arch = if ($x86) { "/x86" } else { "/x64" }

# Resolve to absolute paths. If these are blank/relative, Aut2exe falls back to
# opening its GUI - so validate before launching.
$mainFull = (Resolve-Path $main).Path
if ([string]::IsNullOrWhiteSpace($mainFull)) { throw "Could not resolve main.au3 path" }
$argList = @('/in', $mainFull, '/out', $outExe, $arch, '/nopack')
Write-Host ("Running: Aut2exe.exe " + ($argList -join ' '))

# Use Start-Process -Wait (reliable headless compile; avoids the call-operator
# handing a GUI-subsystem exe off in a way that can pop the converter window).
$proc = Start-Process -FilePath $aut2exe -ArgumentList $argList -Wait -PassThru -NoNewWindow
Write-Host "Aut2exe exit code: $($proc.ExitCode)"

if (Test-Path $outExe) {
    $sz = [math]::Round((Get-Item $outExe).Length/1MB, 2)
    Write-Host "`nBUILD OK -> $outExe  ($sz MB)" -ForegroundColor Green
    Write-Host "Note: it will request admin rights on launch (#RequireAdmin)."
} else {
    Write-Host "`nBUILD FAILED - no exe produced. Check the Aut2exe output above." -ForegroundColor Red
    Write-Host "Most common cause: a FileInstall source file is missing or in the wrong folder."
}
