# ServicePro Windows/Firebase C++ SDK build recovery.
# Run in Windows PowerShell from the project folder:
# powershell -NoProfile -ExecutionPolicy Bypass -File .\repair_windows_firebase.ps1
# Only generated Flutter build files and this script's own SDK cache are cleaned.
param([switch]$BuildOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot

function Assert-Exit([string]$name) {
    if ($LASTEXITCODE -ne 0) {
        throw "$name failed (exit code: $LASTEXITCODE)."
    }
}

function Test-Sdk([string]$directory, [string]$expectedVersion) {
    $headerPath = Join-Path $directory 'include\firebase\version.h'
    $cmakePath = Join-Path $directory 'CMakeLists.txt'
    if (-not (Test-Path -LiteralPath $headerPath) -or
        -not (Test-Path -LiteralPath $cmakePath)) { return $false }
    $header = Get-Content -LiteralPath $headerPath -Raw
    $major = [regex]::Match($header, 'FIREBASE_VERSION_MAJOR\s+(\d+)').Groups[1].Value
    $minor = [regex]::Match($header, 'FIREBASE_VERSION_MINOR\s+(\d+)').Groups[1].Value
    $revision = [regex]::Match($header, 'FIREBASE_VERSION_REVISION\s+(\d+)').Groups[1].Value
    if ("$major.$minor.$revision" -ne $expectedVersion) { return $false }
    $appLibraries = @(Get-ChildItem -LiteralPath $directory -Filter 'firebase_app.lib' -File -Recurse -ErrorAction SilentlyContinue)
    return $appLibraries.Count -gt 0
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter PATH ichida topilmadi. Avval Flutter SDK va Windows desktop supportni sozlang.'
}
if ($project -match '(?i)OneDrive|Dropbox|Google Drive') {
    Write-Warning 'Loyiha sinxronlanadigan papkada. Windows build uchun C:\dev\ServicePro kabi OneDrive tashqarisidagi joy tavsiya qilinadi.'
}

Push-Location -LiteralPath $project
try {
    Write-Host '[1/5] Flutter bogliqliklarini tekshirish...' -ForegroundColor Cyan
    & flutter pub get
    Assert-Exit 'flutter pub get'

    $lockFile = Join-Path $project 'pubspec.lock'
    if (-not (Test-Path -LiteralPath $lockFile)) { throw 'pubspec.lock topilmadi.' }
    $lock = Get-Content -LiteralPath $lockFile -Raw
    $corePart = [regex]::Match($lock, '(?ms)^  firebase_core:\s*\r?\n(.*?)(?=^  \S|\z)')
    if (-not $corePart.Success) { throw 'pubspec.lock ichida firebase_core topilmadi.' }
    $coreMatch = [regex]::Match($corePart.Groups[1].Value, '(?m)^    version:\s*"([0-9]+\.[0-9]+\.[0-9]+)"')
    if (-not $coreMatch.Success) { throw 'firebase_core versiyasi aniqlanmadi.' }
    $coreVersion = $coreMatch.Groups[1].Value

    $pubCache = if ($env:PUB_CACHE) { $env:PUB_CACHE } else { Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
    $coreCmake = Join-Path $pubCache "hosted\pub.dev\firebase_core-$coreVersion\windows\CMakeLists.txt"
    if (-not (Test-Path -LiteralPath $coreCmake)) {
        throw "Firebase Windows CMake topilmadi: $coreCmake"
    }
    $cmake = Get-Content -LiteralPath $coreCmake -Raw
    if ($cmake -notmatch 'FIREBASE_CPP_SDK_DIR') {
        throw 'Ushbu firebase_core versiyasi FIREBASE_CPP_SDK_DIR ni qollamasligi mumkin. Paketni avtomatik ozgartirmaymiz.'
    }
    $sdkMatch = [regex]::Match($cmake, 'set\(FIREBASE_SDK_VERSION\s+"?([0-9]+\.[0-9]+\.[0-9]+)"?\)')
    if (-not $sdkMatch.Success) { throw 'Firebase C++ SDK versiyasini CMake faylidan topib bolmadi.' }
    $sdkVersion = $sdkMatch.Groups[1].Value
    Write-Host "firebase_core $coreVersion / Firebase C++ SDK $sdkVersion"

    $cache = Join-Path $env:LOCALAPPDATA "ServicePro\firebase-cpp-sdk\$sdkVersion"
    $sdkDirectory = Join-Path $cache 'firebase_cpp_sdk_windows'
    $zipFile = Join-Path $cache "firebase_cpp_sdk_windows_$sdkVersion.zip"
    $staging = Join-Path $cache 'extracting'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null

    if (-not (Test-Sdk $sdkDirectory $sdkVersion)) {
        Write-Host '[2/5] Firebase SDK ni mustaqil yuklab, ZIP ni toliq ochib tekshirish...' -ForegroundColor Cyan
        $url = "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_windows_$sdkVersion.zip"
        $ready = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            if (Test-Path -LiteralPath $staging) {
                Remove-Item -LiteralPath $staging -Recurse -Force
            }
            New-Item -ItemType Directory -Path $staging | Out-Null
            try {
                if (-not (Test-Path -LiteralPath $zipFile)) {
                    $partial = "$zipFile.download"
                    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
                    Write-Host "SDK yuklanmoqda: urinish $attempt/3"
                    Invoke-WebRequest -Uri $url -OutFile $partial -TimeoutSec 600
                    if ((Get-Item -LiteralPath $partial).Length -lt 5MB) { throw 'Yuklangan ZIP juda kichik.' }
                    Move-Item -LiteralPath $partial -Destination $zipFile -Force
                }
                Expand-Archive -LiteralPath $zipFile -DestinationPath $staging -Force
                $candidate = Join-Path $staging 'firebase_cpp_sdk_windows'
                if (-not (Test-Sdk $candidate $sdkVersion)) {
                    throw 'Ochilgan SDK ichida zarur kutubxona yoki mos versiya topilmadi.'
                }
                if (Test-Path -LiteralPath $sdkDirectory) {
                    $oldSdk = Join-Path $cache ('old_sdk_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
                    Move-Item -LiteralPath $sdkDirectory -Destination $oldSdk
                }
                Move-Item -LiteralPath $candidate -Destination $sdkDirectory
                $ready = $true
                break
            } catch {
                Write-Warning "SDK urinish $attempt xato: $_"
                if (Test-Path -LiteralPath $zipFile) {
                    $broken = "$zipFile.invalid_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                    Move-Item -LiteralPath $zipFile -Destination $broken -Force
                }
                if ($attempt -eq 3) { throw 'Firebase C++ SDK ni soglom holatda yuklab bolmadi. Internet, disk va antivirusni tekshiring.' }
                Start-Sleep -Seconds (3 * $attempt)
            }
        }
        if (-not $ready) { throw 'SDK tayyorlanmadi.' }
    } else {
        Write-Host '[2/5] Oldindan tekshirilgan Firebase SDK keshdan ishlatiladi.' -ForegroundColor Green
    }

    # Official FlutterFire CMake uses this env var and skips a fresh SDK ZIP download.
    $env:FIREBASE_CPP_SDK_DIR = $sdkDirectory
    Write-Host "[3/5] FIREBASE_CPP_SDK_DIR=$sdkDirectory" -ForegroundColor Cyan
    Write-Host '[4/5] Faqat generatsiya qilingan Flutter build keshini tozalash...' -ForegroundColor Cyan
    & flutter clean
    Assert-Exit 'flutter clean'
    & flutter pub get
    Assert-Exit 'flutter pub get'

    Write-Host '[5/5] Windows qayta yigilyapti...' -ForegroundColor Cyan
    if ($BuildOnly) {
        & flutter build windows --debug
        Assert-Exit 'flutter build windows --debug'
    } else {
        & flutter run -d windows
        Assert-Exit 'flutter run -d windows'
    }
    Write-Host 'Firebase Windows SDK bilan ishga tushirish muvaffaqiyatli.' -ForegroundColor Green
} finally {
    Pop-Location
}
