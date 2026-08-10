$ErrorActionPreference = "Stop"

Write-Host "Installing sucata..."

$hasExpandArchive = Get-Command Expand-Archive -ErrorAction SilentlyContinue
$has7zip = Get-Command 7z -ErrorAction SilentlyContinue

if (-not $hasExpandArchive -and -not $has7zip) {
    Write-Error "Needs Expand-Archive (PowerShell) or 7z to install Sucata"
    exit 1
}

$TARGET = "sucata-win-amd64"

$SUCATA_VERSION = (Invoke-RestMethod -Uri "https://api.github.com/repos/sucata-engine/sucata-engine/releases/latest").tag_name

if (-not $SUCATA_VERSION) {
    Write-Error "Could not determine latest sucata version"
    exit 1
}

Write-Host "Latest sucata version: $SUCATA_VERSION"
$SUCATA_NAME = "sucata.exe"
$SUCATA_URL = "https://github.com/sucata-engine/sucata-engine/releases/download/$SUCATA_VERSION/$TARGET.zip"
$SUCATA_DIR = Join-Path $HOME "sucata"
$TEMP_ZIP = Join-Path $SUCATA_DIR "temp.zip"
$BIN_PATH = Join-Path $SUCATA_DIR $SUCATA_NAME

New-Item -ItemType Directory -Force -Path $SUCATA_DIR | Out-Null

Write-Host "Downloading $SUCATA_URL"
Invoke-WebRequest -Uri $SUCATA_URL -OutFile $TEMP_ZIP -UseBasicParsing

if ($hasExpandArchive) {
    Expand-Archive -Path $TEMP_ZIP -DestinationPath $SUCATA_DIR -Force
} else {
    7z x $TEMP_ZIP "-o$SUCATA_DIR" -y | Out-Null
}

Write-Host "Sucata installed at $BIN_PATH"

$CURRENT_PATH = [Environment]::GetEnvironmentVariable("PATH", "User")

if ($CURRENT_PATH -notlike "*$SUCATA_DIR*") {
    [Environment]::SetEnvironmentVariable(
        "PATH",
        "$SUCATA_DIR;$CURRENT_PATH",
        "User"
    )
    Write-Host "Added $SUCATA_DIR to PATH"
} else {
    Write-Host "PATH already contains $SUCATA_DIR"
}

Remove-Item $TEMP_ZIP

Write-Host "Done! Restart your terminal to use sucata."
Write-Host "Sucata installed on $SUCATA_DIR"
