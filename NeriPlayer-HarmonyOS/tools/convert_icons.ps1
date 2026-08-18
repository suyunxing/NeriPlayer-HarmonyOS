param(
    [string]$SourceDir = "E:\music\NeriPlayer-master\app\src\main\res\drawable",
    [string]$OutDir = "E:\music\NeriPlayer-HarmonyOS\entry\src\main\resources\base\media"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$names = @(
    "ic_bilibili", "ic_netease_cloud_music", "ic_youtube", "ic_github", "ic_qq_music",
    "ic_download", "ic_lyrics_24", "ic_lyrics_off_24", "ic_statusbar", "ic_lyricon",
    "ic_arrow_back_24", "ic_baseline_favorite_24", "ic_outline_favorite_24",
    "outline_refresh_24", "round_pause_24", "round_play_arrow_24",
    "round_skip_next_24", "round_skip_previous_24", "ic_neriplayer"
)

function Convert-FillColor([string]$color) {
    if ($color -match '^#([0-9A-Fa-f]{8})$') {
        return "#$($Matches[1].Substring(2))"
    }
    if ($color -match '^#([0-9A-Fa-f]{6})$') {
        return "#$($Matches[1])"
    }
    if ($color -match 'white') {
        return "#FFFFFF"
    }
    if ($color -match 'black') {
        return "#000000"
    }
    # Theme-dependent colors (tints) become white; the UI tints them via Image.fillColor.
    return "#FFFFFF"
}

foreach ($name in $names) {
    $xmlPath = Join-Path $SourceDir "$name.xml"
    if (-not (Test-Path -LiteralPath $xmlPath)) {
        Write-Warning "Missing: $name.xml"
        continue
    }
    [xml]$xml = Get-Content -Raw -LiteralPath $xmlPath
    $vector = $xml.vector
    $vw = $vector.viewportWidth
    $vh = $vector.viewportHeight
    $w = $vector.width
    $h = $vector.height
    $width = if ($w -match '^([\d.]+)dp$') { $Matches[1] } else { $vw }
    $height = if ($h -match '^([\d.]+)dp$') { $Matches[1] } else { $vh }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<svg xmlns=""http://www.w3.org/2000/svg"" width=""$width"" height=""$height"" viewBox=""0 0 $vw $vh"">")
    foreach ($path in $vector.path) {
        $d = $path.pathData
        if (-not $d) { continue }
        $fill = Convert-FillColor $path.fillColor
        [void]$sb.AppendLine("  <path d=""$d"" fill=""$fill""/>")
    }
    [void]$sb.AppendLine("</svg>")
    $outPath = Join-Path $OutDir "$name.svg"
    Set-Content -LiteralPath $outPath -Value $sb.ToString() -Encoding utf8
    Write-Output "converted: $name"
}
