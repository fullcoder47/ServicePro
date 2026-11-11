param([Parameter(Mandatory=$true)][string]$ProjectPath, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Normalize([string]$s) { return $s.Replace("`r`n", "`n") }
function Hash([string]$s) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)))).Replace('-', '').ToLowerInvariant() }
  finally { $h.Dispose() }
}
$root = [IO.Path]::GetFullPath($ProjectPath).TrimEnd([IO.Path]::DirectorySeparatorChar)
if (!(Test-Path (Join-Path $root 'pubspec.yaml'))) { throw 'Flutter project pubspec.yaml not found.' }
$manifest = Get-Content (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$planned = @()
foreach ($entry in $manifest) {
  if ($entry.path -match '(^/|\\|:|(^|/)\.\.(/|$))') { throw 'Invalid package path.' }
  $target = Join-Path $root $entry.path
  $payload = Normalize ([IO.File]::ReadAllText((Join-Path $PSScriptRoot ('files/' + $entry.path))))
  if ((Hash $payload) -ne $entry.after) { throw "Corrupt package: $($entry.path)" }
  $exists = Test-Path $target
  $original = $null
  if ($exists) {
    $original = [IO.File]::ReadAllBytes($target)
    $current = Normalize ([IO.File]::ReadAllText($target))
    if ((Hash $current) -eq $entry.after) { continue }
    if ($null -eq $entry.before) { throw "New file already exists with different content: $($entry.path). No files changed." }
    if ((Hash $current) -eq $entry.before) { $updated = $payload }
    else {
      $updated = $current
      foreach ($chunk in $entry.chunks) {
        $old = [string]$chunk.old
        if ($old.Length -eq 0) { throw "Manual merge required: $($entry.path). No files changed." }
        $at = $updated.IndexOf($old, [StringComparison]::Ordinal)
        if ($at -lt 0 -or $updated.IndexOf($old, $at + $old.Length, [StringComparison]::Ordinal) -ge 0) {
          throw "Conflicting local changes: $($entry.path). No files changed. Send this file for a manual merge."
        }
        $updated = $updated.Substring(0, $at) + [string]$chunk.new + $updated.Substring($at + $old.Length)
      }
    }
  } else {
    if ($null -ne $entry.before) { throw "Existing project file missing: $($entry.path). No files changed." }
    $updated = $payload
  }
  $planned += [PSCustomObject]@{Path=$target; Relative=$entry.path; Content=$updated; Original=$original; Existed=$exists}
}
Write-Host "Preflight passed: $($planned.Count) files to update."
if ($CheckOnly -or $planned.Count -eq 0) { return }
$backup = Join-Path $root ('servicepro-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
[IO.Directory]::CreateDirectory($backup) | Out-Null
foreach ($item in $planned) {
  if ($item.Existed) {
    $dest = Join-Path $backup $item.Relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null
    [IO.File]::WriteAllBytes($dest, $item.Original)
  }
}
$written = @()
try {
  foreach ($item in $planned) {
    $written += $item
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Path)) | Out-Null
    [IO.File]::WriteAllText($item.Path, $item.Content, $utf8)
  }
} catch {
  foreach ($item in $written) {
    if ($item.Existed) { [IO.File]::WriteAllBytes($item.Path, $item.Original) }
    elseif (Test-Path $item.Path) { Remove-Item -LiteralPath $item.Path }
  }
  throw
}
Write-Host "Source update complete. Backup: $backup"
Write-Host 'Backend deployment and Flutter/device checks are still required. Read README_UZ.md.'
