param(
  [Parameter(Mandatory=$true)][string]$Player,
  [Parameter(Mandatory=$true)][string]$Version,
  [string]$ReferencePlayer = ''
)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Player).Path
$v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
if ($v.ProductName -ne 'graal-delphi' -or $v.CompanyName -ne 'squirelworks' -or
    $v.ProductVersion -ne $Version) { throw "Incorrect player version metadata: $($v.ProductVersion)" }
$bytes = [IO.File]::ReadAllBytes($exe)
if ($ReferencePlayer) {
  $reference = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ReferencePlayer).Path)
  if ($bytes.Length -ne $reference.Length) { throw 'Packaged player byte length differs' }
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -ne $reference[$i]) { throw 'Packaged player bytes differ' }
  }
  Write-Output 'Packaged player bytes exactly match the built player'
}
if (-not [Text.Encoding]::ASCII.GetString($bytes).Contains('requestedExecutionLevel')) {
  throw 'Player has no embedded application manifest'
}
# Inspect imports, but report names only, never the PE address/offset dump.
$dump = & objdump -p $exe
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect player imports' }
$imports = @($dump | Select-String 'DLL Name:\s*(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value })
if ($imports.Count -eq 0) { throw 'No PE import records found' }
$system = '^(KERNEL32|USER32|GDI32|ADVAPI32|WS2_32|SHELL32|OLE32|OLEAUT32|COMDLG32|COMCTL32|IMM32|VERSION|WINMM|NTDLL|UCRTBASE|MSVCRT|BCRYPT|CRYPT32|SETUPAPI)\.dll$'
foreach ($dll in $imports) {
  if ($dll -notmatch $system -and $dll -notmatch '^(api-ms-win-|ext-ms-win-).+\.dll$') {
    throw "Unpackaged non-system runtime dependency: $dll"
  }
}
Write-Output ("Player metadata {0}; system imports: {1}" -f $Version, ($imports -join ', '))
# Run only argument validation: --help exits 2 before window/network setup.
# The child has no compiler/MSYS DLL path and runs beside the packaged player.
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $exe
$info.Arguments = '--help'
$info.WorkingDirectory = [IO.Path]::GetDirectoryName($exe)
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$info.EnvironmentVariables['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
$p = New-Object Diagnostics.Process
$p.StartInfo = $info
if (-not $p.Start()) { throw 'Player did not start' }
if (-not $p.WaitForExit(10000)) { $p.Kill(); throw 'Player argument check timed out' }
$out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()
if ($p.ExitCode -ne 2 -or $out -notmatch 'usage: quattro-play') {
  throw "Isolated player argument check failed: exit $($p.ExitCode)"
}
Write-Output 'Isolated packaged player starts without toolchain DLL paths'
