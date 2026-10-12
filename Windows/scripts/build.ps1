param([ValidateSet('win-x64','win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$projectRoot = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $projectRoot "artifacts\$Runtime"
$staging = Join-Path $projectRoot ('artifacts\staging-' + [guid]::NewGuid().ToString('N'))
try {
    dotnet run --project "$projectRoot\PrimeSieve.Tests" -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Regression checks failed.' }
    dotnet run --project "$projectRoot\PrimeSieve.UiTests" -c Release
    if ($LASTEXITCODE -ne 0) { throw 'WPF regression checks failed.' }
    dotnet publish "$projectRoot\PrimeSieve.App" -c Release -r $Runtime --self-contained true -o $staging --nologo
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed; existing package preserved.' }
    if (!(Test-Path "$staging\PrimeSieve.exe") -or !(Test-Path "$staging\Workers\sieve.cs") -or !(Test-Path "$staging\WindowsWorkers\clock.c")) { throw 'Published files are incomplete.' }
    if (Test-Path $destination) {
        $backup = "$destination.previous-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Move-Item $destination $backup
    }
    Move-Item $staging $destination
    $archive = "$destination.zip"
    Compress-Archive -Path "$destination\*" -DestinationPath $archive -Force
    (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + (Split-Path $archive -Leaf) | Set-Content "$archive.sha256"
    Write-Host "Portable app: $destination\PrimeSieve.exe"
    Write-Host "Archive: $archive"
} finally {
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
}
