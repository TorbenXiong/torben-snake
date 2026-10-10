param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
$projectText = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
if ($projectText -notmatch '(?m)^config/version="(\d+\.\d+\.\d+)"\r?$') {
    throw 'project.godot must define a semantic config/version.'
}
$version = $Matches[1]
$releaseDir = Join-Path $projectRoot "build/release/$version"
# A fresh staging directory prevents older exports from entering the Web archive.
$webStage = Join-Path $projectRoot ('build/web-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $releaseDir, $webStage | Out-Null
$windowsPath = Join-Path $releaseDir "TorbenSnake-$version.exe"

New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'build/web') | Out-Null
Set-Content -LiteralPath (Join-Path $projectRoot 'build/.gdignore') -Value '' -NoNewline
& $GodotPath --headless --path $projectRoot --editor --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
& $GodotPath --headless --path $projectRoot --script res://tests/test_game.gd
if ($LASTEXITCODE -ne 0) { throw 'Game tests failed.' }
& $GodotPath --headless --path $projectRoot --script res://tests/test_ui.gd
if ($LASTEXITCODE -ne 0) { throw 'UI tests failed.' }
& $GodotPath --headless --path $projectRoot --export-release 'Windows Desktop' $windowsPath
if ($LASTEXITCODE -ne 0) { throw 'Windows export failed.' }
& $GodotPath --headless --path $projectRoot --export-release 'Web' (Join-Path $webStage 'index.html')
if ($LASTEXITCODE -ne 0) { throw 'Web export failed.' }
$licensePath = Join-Path $projectRoot 'assets/fonts/OFL.txt'
Copy-Item -LiteralPath $licensePath -Destination $releaseDir
Copy-Item -LiteralPath $licensePath -Destination $webStage
$webZip = Join-Path $releaseDir "TorbenSnake-$version-web.zip"
Compress-Archive -Path (Join-Path $webStage '*') -DestinationPath $webZip -Force
Copy-Item -Path (Join-Path $webStage '*') -Destination (Join-Path $projectRoot 'build/web') -Force
Copy-Item -LiteralPath $windowsPath -Destination (Join-Path $projectRoot 'build/torben_snake_windows.exe')
$checksums = foreach ($file in @($windowsPath, $webZip, (Join-Path $releaseDir 'OFL.txt'))) {
    $hash = Get-FileHash -LiteralPath $file -Algorithm SHA256
    '{0}  {1}' -f $hash.Hash, (Split-Path -Leaf $file)
}
Set-Content -LiteralPath (Join-Path $releaseDir 'SHA256SUMS.txt') -Value $checksums -Encoding ascii
# Delete only the staging directory created by this invocation, inside build/.
$buildRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build')) + [IO.Path]::DirectorySeparatorChar
if (-not [IO.Path]::GetFullPath($webStage).StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Web staging directory is outside build/.'
}
Remove-Item -LiteralPath $webStage -Recurse -Force
Write-Output "Tests passed. Release $version is ready at $releaseDir."
