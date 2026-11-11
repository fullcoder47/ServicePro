$ErrorActionPreference = "Stop"

# ServicePro build fix: Android Studio 2026 may bundle JDK 25.0.2,
# while this project's Gradle/Kotlin toolchain expects JDK 17/21.
# This script does not change Flutter/Dart app code or business logic.

$candidates = @(
  "$env:JAVA_HOME",
  "C:\Program Files\Java\jdk-21",
  "C:\Program Files\Java\jdk-17",
  "C:\Program Files\Eclipse Adoptium\jdk-21*",
  "C:\Program Files\Eclipse Adoptium\jdk-17*"
)

$jdk = $null
foreach ($candidate in $candidates) {
  if (-not $candidate) { continue }
  $resolved = Get-ChildItem -Path $candidate -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($resolved) { $candidate = $resolved.FullName }
  if (Test-Path (Join-Path $candidate 'bin\java.exe')) {
    $jdk = (Resolve-Path $candidate).Path
    break
  }
}

if (-not $jdk) {
  $androidJbr = 'C:\Program Files\Android\Android Studio\jbr'
  if (Test-Path (Join-Path $androidJbr 'bin\java.exe')) {
    $version = & (Join-Path $androidJbr 'bin\java.exe') -version 2>&1 | Select-String 'version'
    if ($version -match '"(17|18|19|20|21)\.') {
      $jdk = (Resolve-Path $androidJbr).Path
    }
  }
}

if (-not $jdk) {
  Write-Host 'JDK 17 yoki JDK 21 topilmadi.' -ForegroundColor Red
  Write-Host 'Android Studio/Temurin JDK 17 yoki 21 o''rnating, so''ng ushbu scriptni yana ishga tushiring.'
  exit 1
}

Write-Host "Using JDK: $jdk" -ForegroundColor Green
& flutter config --jdk-dir="$jdk"
$env:JAVA_HOME = $jdk
$env:Path = "$jdk\bin;$env:Path"
java -version
flutter doctor -v
Write-Host "Tayyor. Endi ServicePro papkasida: flutter clean; flutter pub get; flutter run" -ForegroundColor Green
