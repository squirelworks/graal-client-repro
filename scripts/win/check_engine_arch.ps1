# Existing Pascal-host execution receipts prove loading in the CI environment.
# This gate does not establish portable package/runtime dependency closure.
[CmdletBinding()]
param(
    [string]$BuildRoot = (Join-Path $PSScriptRoot '../../build'),
    [ValidateSet('BeforeTests', 'AfterTests')]
    [string]$Phase = 'AfterTests'
)
$ErrorActionPreference = 'Stop'

function Assert-I386Pe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required engine artifact missing: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    # DOS header contains e_lfanew at byte 60; inspect only bounded offsets.
    if ($bytes.LongLength -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) {
        throw "Invalid DOS header: $Path"
    }
    $pe = [uint64][BitConverter]::ToUInt32($bytes, 60)
    # Signature + complete COFF header must fit before converting to Int32.
    if ($pe -lt 64 -or $pe -gt ([uint64]$bytes.LongLength - 24) -or $pe -gt [int]::MaxValue) {
        throw "PE header offset outside file: $Path"
    }
    $offset = [int]$pe
    if ($bytes[$offset] -ne 0x50 -or $bytes[$offset + 1] -ne 0x45 -or
        $bytes[$offset + 2] -ne 0 -or $bytes[$offset + 3] -ne 0) {
        throw "Invalid PE signature: $Path"
    }
    if ([BitConverter]::ToUInt16($bytes, $offset + 4) -ne 0x014c) {
        throw "Expected PE i386 artifact: $Path"
    }
    Write-Host "PE i386: $Path"
}

function Assert-HostReceipt([string]$Exe, [bool]$Require3D) {
    foreach ($suffix in @('.out', '.rc', '.heap')) {
        if (-not (Test-Path -LiteralPath ($Exe + $suffix) -PathType Leaf)) {
            throw "Missing scripts/test.sh receipt: $Exe$suffix"
        }
    }
    $output = [IO.File]::ReadAllText($Exe + '.out')
    $lines = $output -split '\r?\n'
    if ($output -match '(?im)^skip engine library tests:') {
        throw "Pascal engine loading was skipped: $Exe"
    }
    $markers = @(
        'ok   graal_engineInitialize returns success',
        'all checks passed'
    )
    foreach ($marker in $markers) {
        if ($lines -cnotcontains $marker) { throw "Missing execution marker '$marker': $Exe" }
    }
    # The existing check appends the loader's error string after the DLL name.
    if (-not ($lines | Where-Object { $_ -cmatch '^ok   loads GraalEngineRepro\.dll(?: |$)' })) {
        throw "Missing actual Pascal engine-load marker: $Exe"
    }
    if ($Require3D) {
        foreach ($marker in @(
            'ok   the launcher loads Graal3DEngineRepro.dll',
            'ok   unloads the 3D library too'
        )) {
            if ($lines -cnotcontains $marker) { throw "Missing execution marker '$marker': $Exe" }
        }
    }
    if ([IO.File]::ReadAllText($Exe + '.rc').Trim() -cne '0') {
        throw "Pascal host did not exit successfully: $Exe"
    }
    if ([IO.File]::ReadAllText($Exe + '.heap') -notmatch '(?m)^0 unfreed memory blocks\b') {
        throw "Pascal host lacks a zero-leak receipt: $Exe"
    }
    Write-Host "Pascal engine execution verified: $Exe"
}

$targets = @(
    @{ Folder = 'graal-4.04r2-G3D17026'; HostExe = 'TestEngineHost404.exe'; Require3D = $false },
    @{ Folder = 'graal-5.12-G3D14097'; HostExe = 'TestEngineHost512.exe'; Require3D = $true }
)
$checked = 0
foreach ($target in $targets) {
    $folder = Join-Path $BuildRoot $target.Folder
    if (-not (Test-Path -LiteralPath $folder)) {
        Write-Host "Not selected/built; skipping engine artifact gate: $($target.Folder)"
        continue
    }
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        throw "Expected build directory: $folder"
    }
    foreach ($name in @('GraalEngineRepro.dll', 'Graal3DEngineRepro.dll', $target.HostExe)) {
        Assert-I386Pe (Join-Path $folder $name)
    }
    if ($Phase -eq 'AfterTests') {
        Assert-HostReceipt (Join-Path $folder $target.HostExe) $target.Require3D
    }
    $checked++
}
Write-Host "Engine gate ($Phase): verified $checked selected build folder(s). CI loader environment only."
