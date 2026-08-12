param(
    [string]$BundleName = "moe.ouom.neriplayer",
    [string]$VersionName = "1.0.0",
    [int]$VersionCode = 1000000,
    [Parameter(Mandatory = $true)]
    [string]$SdkHome,
    [Parameter(Mandatory = $true)]
    [string[]]$DeviceIds,
    [Parameter(Mandatory = $true)]
    [string]$OutFile
)

$ErrorActionPreference = "Stop"
$profilePem = Join-Path $SdkHome "default\openharmony\toolchains\lib\OpenHarmonyProfileDebug.pem"
if (-not (Test-Path -LiteralPath $profilePem)) {
    throw "OpenHarmony debug profile certificate not found: $profilePem"
}

$normalizedDeviceIds = @($DeviceIds | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
if ($normalizedDeviceIds.Count -eq 0) {
    throw "At least one debug device UDID is required."
}

$pem = Get-Content -Raw -LiteralPath $profilePem
$blocks = [regex]::Matches(
    $pem,
    "-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
    "Singleline")
if ($blocks.Count -lt 3) {
    throw "Unexpected certificate chain in $profilePem (expected at least three certificates)."
}

$leafPemBlock = $blocks[$blocks.Count - 1].Value
$leafCert = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
    [Text.Encoding]::ASCII.GetBytes($leafPemBlock))
$leafDerBase64 = [Convert]::ToBase64String($leafCert.RawData).Replace('+', '-').Replace('/', '_').TrimEnd('=')

$profile = @{
    "version-name" = $VersionName
    "version-code" = $VersionCode
    "uuid" = [Guid]::NewGuid().ToString()
    "validity" = @{
        "not-before" = [DateTimeOffset]::UtcNow.AddDays(-1).ToUnixTimeSeconds()
        "not-after" = [DateTimeOffset]::UtcNow.AddYears(1).ToUnixTimeSeconds()
    }
    "type" = "debug"
    "bundle-info" = @{
        "developer-id" = "OpenHarmony"
        "development-certificate" = $leafDerBase64
        "bundle-name" = $BundleName
        "apl" = "normal"
        "app-feature" = "hos_normal_app"
    }
    "acls" = @{ "allowed-acls" = @() }
    "permissions" = @{ "restricted-permissions" = @() }
    "debug-info" = @{
        "device-ids" = $normalizedDeviceIds
        "device-id-type" = "udid"
    }
    "issuer" = "pki_internal"
}

$outputDirectory = Split-Path -Parent $OutFile
if ($outputDirectory) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$profile | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutFile -Encoding utf8
Write-Output "Prepared debug profile: $OutFile"
