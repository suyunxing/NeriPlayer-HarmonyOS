param([string]$Files, [string]$Points)
Add-Type -AssemblyName System.Drawing
$pts = $Points.Split(',') | ForEach-Object { [int]$_ }
foreach ($f in $Files.Split(',')) {
    $bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path -LiteralPath $f).Path)
    $line = $f + " " + $bmp.Width + "x" + $bmp.Height + " :"
    for ($i = 0; $i -lt $pts.Count; $i += 2) {
        $x = $pts[$i]; $y = $pts[$i + 1]
        if ($x -lt $bmp.Width -and $y -lt $bmp.Height) {
            $c = $bmp.GetPixel($x, $y)
            $line += "  (" + $x + "," + $y + ")=" + $c.R + "," + $c.G + "," + $c.B
        }
    }
    Write-Output $line
    $bmp.Dispose()
}
