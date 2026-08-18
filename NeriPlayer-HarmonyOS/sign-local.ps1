param(
    [string]$Device = "127.0.0.1:5555",
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$sdkHome = "E:\DevEco Studio\sdk"
$signDir = Join-Path $projectRoot "signing"
$hapTool = "E:\DevEco Studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar"
$java = "E:\DevEco Studio\jbr\bin\java.exe"
$hdc = "E:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
$hvigorw = "E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat"
$profilePem = "E:\DevEco Studio\sdk\default\openharmony\toolchains\lib\OpenHarmonyProfileDebug.pem"
$keystore = Join-Path $signDir "OpenHarmony.p12"
$pwd = "NeriPlayerHarmonyOSDebug2026KeyStore!!!"
$outputDir = Join-Path $projectRoot "entry\build\default\outputs\default"
$unsignedHap = Join-Path $outputDir "entry-default-unsigned.hap"
$signedHap = Join-Path $outputDir "entry-default-signed.hap"
$profileJson = Join-Path $signDir "debug-profile.json"
$profileP7b = Join-Path $signDir "debug-profile.p7b"
$certChainDer = Join-Path $signDir "app-cert-chain.der"

if (-not (Test-Path -LiteralPath $keystore)) {
    throw "Missing $keystore. Copy OpenHarmony.p12 from the SDK toolchains\lib and set a 32+ char (odd-length) password once."
}

$env:DEVECO_SDK_HOME = $sdkHome

Write-Host "==> 1/4 Build unsigned HAP"
Push-Location $projectRoot
try {
    & cmd /c "`"$hvigorw`" assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "hvigor build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

Write-Host "==> 2/4 Prepare debug provision profile"
& (Join-Path $signDir "prepare-debug-profile.ps1") -OutFile $profileJson

Write-Host "==> 3/4 Build app cert chain (leaf-first DER)"
$pemContent = Get-Content -Raw -LiteralPath $profilePem
$certBlocks = [regex]::Matches($pemContent, "-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", "Singleline")
if ($certBlocks.Count -lt 3) { throw "Unexpected certificate chain in $profilePem" }
$derBytes = New-Object System.Collections.Generic.List[byte]
foreach ($index in @(2, 1, 0)) {
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        [System.Text.Encoding]::ASCII.GetBytes($certBlocks[$index].Value))
    $derBytes.AddRange([byte[]]$cert.RawData)
}
[System.IO.File]::WriteAllBytes($certChainDer, $derBytes.ToArray())

Write-Host "==> 4/5 Sign profile + HAP"
& $java -jar $hapTool sign-profile -mode localSign `
    -keyAlias "openharmony application profile debug" -keyPwd $pwd `
    -profileCertFile $profilePem -inFile $profileJson -signAlg SHA256withECDSA `
    -keystoreFile $keystore -keystorePwd $pwd -outFile $profileP7b
if ($LASTEXITCODE -ne 0) { throw "sign-profile failed" }

& $java -jar $hapTool sign-app -mode localSign `
    -keyAlias "openharmony application profile debug" -keyPwd $pwd `
    -appCertFile $certChainDer -profileFile $profileP7b -profileSigned 1 `
    -inFile $unsignedHap -signAlg SHA256withECDSA `
    -keystoreFile $keystore -keystorePwd $pwd -outFile $signedHap `
    -compatibleVersion 24 -signCode 1
if ($LASTEXITCODE -ne 0) { throw "sign-app failed" }

Write-Host "==> 5/5 Install to $Device"
if ($SkipInstall) {
    Write-Host "Signed HAP: $signedHap (install skipped)"
} else {
    & $hdc -t $Device install -r $signedHap
    if ($LASTEXITCODE -ne 0) { throw "hdc install failed" }
    Write-Host "Installed. Launch with: hdc shell aa start -a EntryAbility -b moe.ouom.neriplayer -m entry"
}
