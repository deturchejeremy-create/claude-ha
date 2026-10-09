# Prépare le PC Windows pour le projet "satellite vocal OnePlus NE2215" :
# Git for Windows, Claude Code, ADB (platform-tools) et scrcpy.
# Ne touche à rien sur le téléphone, à part un "adb devices" final en lecture.
#
# Lancement (PowerShell, depuis ce dossier) :
#   powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
                "$env:USERPROFILE\.local\bin"
}

function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Install-WingetPackage($id, $cmd) {
    if (Test-Cmd $cmd) {
        Write-Host "[ok] $cmd déjà présent" -ForegroundColor Green
        return
    }
    if (-not (Test-Cmd 'winget')) {
        throw "winget introuvable. Installe 'App Installer' depuis le Microsoft Store puis relance."
    }
    Write-Host "[..] Installation de $id" -ForegroundColor Cyan
    winget install --id $id -e --accept-source-agreements --accept-package-agreements
    Refresh-Path
}

# 1. Git for Windows (requis par Claude Code sous Windows)
Install-WingetPackage 'Git.Git' 'git'

# 2. ADB et scrcpy
Install-WingetPackage 'Google.PlatformTools' 'adb'
Install-WingetPackage 'Genymobile.scrcpy' 'scrcpy'

# 3. Claude Code (installeur officiel)
if (Test-Cmd 'claude') {
    Write-Host "[ok] claude déjà présent" -ForegroundColor Green
} else {
    Write-Host "[..] Installation de Claude Code" -ForegroundColor Cyan
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
    Refresh-Path
}

# 4. Vérification
Write-Host ''
foreach ($c in 'git', 'adb', 'scrcpy', 'claude') {
    if (Test-Cmd $c) { Write-Host "[ok] $c" -ForegroundColor Green }
    else { Write-Host "[!!] $c introuvable : ferme et rouvre PowerShell, puis relance ce script" -ForegroundColor Yellow }
}

if (Test-Cmd 'adb') {
    Write-Host ''
    Write-Host '--- adb devices ---'
    adb devices
    Write-Host 'Le OnePlus doit apparaître en "device". "unauthorized" = valider la popup sur le téléphone (via scrcpy).'
}

Write-Host ''
Write-Host 'Étape suivante : dans ce dossier, tape  claude  puis colle le contenu de PROMPT.md' -ForegroundColor Cyan
