param(
    [string]$Device = "127.0.0.1:5555",
    [switch]$SkipInstall,
    [string]$DevEcoHome = $env:DEVECO_STUDIO_HOME,
    [string]$SdkHome = $env:DEVECO_SDK_HOME,
    [string]$HvigorwPath = $env:DEVECO_HVIGORW,
    [string]$KeystorePath,
    [string]$KeystorePassword = $env:NERIPLAYER_SIGNING_PASSWORD,
    [string[]]$DeviceIds = @(),
    [int]$CompatibleVersion = 24
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot

function Resolve-SdkHome {
    param([string]$ConfiguredPath)

    $candidate = $ConfiguredPath
    if (-not $candidate) {
        $propertiesPath = Join-Path $projectRoot "local.properties"
        if (Test-Path -LiteralPath $propertiesPath) {
            $sdkLine = Get-Content -LiteralPath $propertiesPath |
                Where-Object { $_ -match '^sdk\.dir=' } |
                Select-Object -First 1
            if ($sdkLine) {
                $candidate = ($sdkLine -replace '^sdk\.dir=', '').Replace('/', [IO.Path]::DirectorySeparatorChar)
            }
        }
    }

    if (-not $candidate -or -not (Test-Path -LiteralPath $candidate)) {
        throw "HarmonyOS SDK not found. Set DEVECO_SDK_HOME or update local.properties."
    }

    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    if (Test-Path -LiteralPath (Join-Path $resolved "default\openharmony")) {
        return $resolved
    }
    if (Test-Path -LiteralPath (Join-Path $resolved "openharmony")) {
        return (Split-Path -Parent $resolved)
    }
    throw "Unrecognized HarmonyOS SDK layout: $resolved"
}

function Read-PlainTextPassword {
    $securePassword = Read-Host "OpenHarmony debug keystore password" -AsSecureString
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
}

$sdkHomeResolved = Resolve-SdkHome -ConfiguredPath $SdkHome
if (-not $DevEcoHome) {
    $DevEcoHome = Split-Path -Parent $sdkHomeResolved
}
$DevEcoHome = (Resolve-Path -LiteralPath $DevEcoHome).Path

$toolchainsDir = Join-Path $sdkHomeResolved "default\openharmony\toolchains"
$hapTool = Join-Path $toolchainsDir "lib\hap-sign-tool.jar"
$java = Join-Path $DevEcoHome "jbr\bin\java.exe"
$hdc = Join-Path $toolchainsDir "hdc.exe"
# DevEco Studio 26.0.0 Beta2 hvigor cannot build a 6.1.1(24) project.
# Builds must use the matching command-line-tools hvigorw
# (override via -HvigorwPath or env DEVECO_HVIGORW; falls back to the Studio hvigor).
$hvigorw = $HvigorwPath
if (-not $hvigorw) {
    $hvigorw = Join-Path $DevEcoHome "tools\hvigor\bin\hvigorw.bat"
}
$profilePem = Join-Path $toolchainsDir "lib\OpenHarmonyProfileDebug.pem"
$signDir = Join-Path $projectRoot "signing"
if (-not $KeystorePath) {
    $KeystorePath = Join-Path $signDir "OpenHarmony.p12"
}

$requiredTools = @($hapTool, $java, $hvigorw, $profilePem, $KeystorePath)
if (-not $SkipInstall) {
    $requiredTools += $hdc
}
foreach ($requiredPath in $requiredTools) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required file not found: $requiredPath"
    }
}

if (-not $KeystorePassword) {
    $KeystorePassword = Read-PlainTextPassword
}
if ($KeystorePassword.Length -lt 32) {
    throw "The OpenHarmony debug keystore password must be at least 32 characters."
}

if ($DeviceIds.Count -eq 0 -and $env:NERIPLAYER_DEVICE_IDS) {
    $DeviceIds = @($env:NERIPLAYER_DEVICE_IDS.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($DeviceIds.Count -eq 0) {
    throw "No debug device UDID supplied. Pass -DeviceIds or set NERIPLAYER_DEVICE_IDS."
}

New-Item -ItemType Directory -Path $signDir -Force | Out-Null
$outputDir = Join-Path $projectRoot "entry\build\default\outputs\default"
$unsignedHap = Join-Path $outputDir "entry-default-unsigned.hap"
$signedHap = Join-Path $outputDir "entry-default-signed.hap"
$profileJson = Join-Path $signDir "debug-profile.json"
$profileP7b = Join-Path $signDir "debug-profile.p7b"
$certChainDer = Join-Path $signDir "app-cert-chain.der"
$env:DEVECO_SDK_HOME = $sdkHomeResolved

try {
    Write-Host "==> 1/5 Build unsigned HAP"
    Write-Host "==> hvigorw: $hvigorw"
    Push-Location $projectRoot
    try {
        & $hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
        if ($LASTEXITCODE -ne 0) { throw "hvigor build failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }

    Write-Host "==> 2/5 Prepare debug provision profile"
    & (Join-Path $projectRoot "tools\prepare-debug-profile.ps1") `
        -SdkHome $sdkHomeResolved -DeviceIds $DeviceIds -OutFile $profileJson

    Write-Host "==> 3/5 Build app certificate chain"
    $pemContent = Get-Content -Raw -LiteralPath $profilePem
    $certBlocks = [regex]::Matches(
        $pemContent,
        "-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        "Singleline")
    if ($certBlocks.Count -lt 3) { throw "Unexpected certificate chain in $profilePem" }
    $derBytes = New-Object System.Collections.Generic.List[byte]
    foreach ($index in @(2, 1, 0)) {
        $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
            [Text.Encoding]::ASCII.GetBytes($certBlocks[$index].Value))
        $derBytes.AddRange([byte[]]$cert.RawData)
    }
    [IO.File]::WriteAllBytes($certChainDer, $derBytes.ToArray())

    Write-Host "==> 4/5 Sign profile and HAP"
    & $java -jar $hapTool sign-profile -mode localSign `
        -keyAlias "openharmony application profile debug" -keyPwd $KeystorePassword `
        -profileCertFile $profilePem -inFile $profileJson -signAlg SHA256withECDSA `
        -keystoreFile $KeystorePath -keystorePwd $KeystorePassword -outFile $profileP7b
    if ($LASTEXITCODE -ne 0) { throw "sign-profile failed" }

    & $java -jar $hapTool sign-app -mode localSign `
        -keyAlias "openharmony application profile debug" -keyPwd $KeystorePassword `
        -appCertFile $certChainDer -profileFile $profileP7b -profileSigned 1 `
        -inFile $unsignedHap -signAlg SHA256withECDSA `
        -keystoreFile $KeystorePath -keystorePwd $KeystorePassword -outFile $signedHap `
        -compatibleVersion $CompatibleVersion -signCode 1
    if ($LASTEXITCODE -ne 0) { throw "sign-app failed" }

    Write-Host "==> 5/5 Install"
    if ($SkipInstall) {
        Write-Host "Signed HAP: $signedHap (installation skipped)"
    } else {
        $installOutput = @(& $hdc -t $Device install -r $signedHap 2>&1)
        $installExitCode = $LASTEXITCODE
        $installText = $installOutput -join [Environment]::NewLine
        $installOutput | ForEach-Object { Write-Host $_ }
        if ($installExitCode -ne 0 -or $installText -match '(?m)^\[Fail\]') {
            throw "hdc install failed for target $Device"
        }
        Write-Host "Installed. Launch with: hdc -t $Device shell aa start -a EntryAbility -b moe.ouom.neriplayer -m entry"
    }
} finally {
    $KeystorePassword = $null
}
