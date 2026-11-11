# ServicePro Microsoft Store package review (read-only: extracts a COPY of the MSIX).
# Run from the project root: powershell -ExecutionPolicy Bypass -File .\Check-ServiceProMsix.ps1
param([string]$MsixPath = "")
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($MsixPath)) {
    $package = Get-ChildItem -LiteralPath $root -Filter '*.msix' -File -Recurse |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $package) {
        throw 'MSIX fayl topilmadi. Avval dart run msix:create bajaring.'
    }
    $MsixPath = $package.FullName
}

$msix = (Resolve-Path -LiteralPath $MsixPath).Path
$review = Join-Path (Split-Path -Parent $msix) ('ServicePro_MSIX_Check_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -Path $review -ItemType Directory -Force | Out-Null
$zipCopy = Join-Path $review 'package_copy.zip'
Copy-Item -LiteralPath $msix -Destination $zipCopy
Expand-Archive -LiteralPath $zipCopy -DestinationPath (Join-Path $review 'unpacked')
Remove-Item -LiteralPath $zipCopy
$unpacked = Join-Path $review 'unpacked'
$manifest = Join-Path $unpacked 'AppxManifest.xml'
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "AppxManifest.xml yo'q. MSIX tuzilishini tekshiring: $review"
}
[xml]$xml = Get-Content -LiteralPath $manifest -Raw
$identity = $xml.SelectSingleNode("//*[local-name()='Identity']")
if ($null -eq $identity) { throw 'Manifestda Identity topilmadi.' }

Write-Host "`n=== SERVICEPRO MSIX CHECK ===" -ForegroundColor Cyan
Write-Host "MSIX: $msix"
Write-Host "Package identity: $($identity.GetAttribute('Name'))"
Write-Host "Publisher: $($identity.GetAttribute('Publisher'))"
Write-Host "Version: $($identity.GetAttribute('Version'))"

# Confirm expected values without editing the real package.
$yaml = Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Raw
$expected = @{}
foreach ($field in @('identity_name', 'publisher', 'msix_version')) {
    $regex = '(?m)^\s{2}' + $field + ':\s*["'']?([^\r\n"''#]+)'
    $matchResult = [regex]::Match($yaml, $regex)
    if ($matchResult.Success) { $expected[$field] = $matchResult.Groups[1].Value.Trim() }
}
$actual = @{ identity_name = $identity.GetAttribute('Name'); publisher = $identity.GetAttribute('Publisher'); msix_version = $identity.GetAttribute('Version') }
foreach ($field in $expected.Keys) {
    if ($actual[$field] -ne $expected[$field]) {
        throw "$field mismatch! Expected '$($expected[$field])', got '$($actual[$field])'."
    }
}
Write-Host 'Identity/Publisher/Version: pubspec.yaml bilan mos.' -ForegroundColor Green

# Windows tile/logo references in the package manifest.
$logoRefs = New-Object System.Collections.Generic.List[string]
foreach ($node in $xml.SelectNodes('//*')) {
    if ($null -eq $node.Attributes) { continue }
    foreach ($attr in $node.Attributes) {
        if ($attr.LocalName -match '(Logo|Image)$' -and $attr.Value -match '\.(png|jpg|jpeg)$') {
            if (-not $logoRefs.Contains($attr.Value)) { $logoRefs.Add($attr.Value) }
        }
    }
}
Write-Host "`nManifestdagi logo yo'llari:"
foreach ($ref in $logoRefs) { Write-Host " - $ref" }
if ($logoRefs.Count -eq 0) { Write-Warning 'Manifestda PNG logo referenslari topilmadi.' }

$images = @(Get-ChildItem -LiteralPath $unpacked -Include '*.png','*.jpg','*.jpeg' -File -Recurse)
Write-Host "`nMSIX ichidagi rasm fayllari: $($images.Count)"
if ($images.Count -eq 0) { throw 'MSIX ichida rasm fayllari topilmadi!' }
foreach ($img in ($images | Select-Object -First 30)) {
    Write-Host (' - ' + $img.FullName.Substring($unpacked.Length + 1) + ' (' + $img.Length + ' bytes)')
}

Write-Host "`nTekshiruv uchun ochilgan papka: $unpacked" -ForegroundColor Cyan
Write-Host 'MUHIM: Assets ichidagi Start/Tile PNG larni ochib, ServicePro oltin logotipi ekanini KOZ BILAN tekshiring.' -ForegroundColor Yellow
Write-Host 'Microsoft Windows App Certification Kit (WACK) orqali ham testdan otkazing.' -ForegroundColor Yellow
Start-Process explorer.exe -ArgumentList ('"' + $unpacked + '"')
