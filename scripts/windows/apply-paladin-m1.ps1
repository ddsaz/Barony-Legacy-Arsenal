#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & git -C $script:RepoPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git falló con código ${LASTEXITCODE}: git $($Arguments -join ' ')"
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        $RepoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    }
    else {
        $RepoPath = [IO.Path]::GetFullPath($RepoPath)
    }
    $script:RepoPath = $RepoPath

    $sourcePath = Join-Path $RepoPath "src\items.cpp"
    $headerPath = Join-Path $RepoPath "src\legacy_arsenal.hpp"

    foreach ($requiredPath in @($sourcePath, $headerPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "No existe la ruta requerida: $requiredPath"
        }
    }

    $branch = (& git -C $RepoPath branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo determinar la rama actual."
    }
    if ($branch -ne "feature/paladin-legacy-sword") {
        throw "La rama actual es '$branch'. Cambia primero a feature/paladin-legacy-sword."
    }

    $status = @(& git -C $RepoPath status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo consultar el estado de Git."
    }
    if ($status.Count -gt 0) {
        throw @"
El árbol de trabajo no está limpio:

$($status -join [Environment]::NewLine)

Confirma primero el hito M0 antes de aplicar M1.
"@
    }

    $originalBytes = [IO.File]::ReadAllBytes($sourcePath)
    $text = [Text.Encoding]::UTF8.GetString($originalBytes)
    $lineEnding = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

    $includeLine = '#include "legacy_arsenal.hpp"'
    if (-not $text.Contains($includeLine)) {
        $includeAnchor = '#include "mod_tools.hpp"'
        $includeIndex = $text.IndexOf($includeAnchor, [StringComparison]::Ordinal)
        if ($includeIndex -lt 0) {
            throw "No se encontró el include de referencia mod_tools.hpp."
        }
        $insertAt = $includeIndex + $includeAnchor.Length
        $text = $text.Insert($insertAt, $lineEnding + $includeLine)
    }

    $descriptionStartAnchor = 'char* Item::description() const'
    $descriptionEndAnchor = 'Category itemCategory(const Item* const item)'
    $descriptionStart = $text.IndexOf($descriptionStartAnchor, [StringComparison]::Ordinal)
    $descriptionEnd = $text.IndexOf($descriptionEndAnchor, $descriptionStart, [StringComparison]::Ordinal)
    if ($descriptionStart -lt 0 -or $descriptionEnd -lt 0) {
        throw "No se pudo localizar Item::description()."
    }

    $descriptionBlock = $text.Substring($descriptionStart, $descriptionEnd - $descriptionStart)
    $oldAppend = 'snprintf(&tempstr[c], 1024 - c, "%s", items[type].getIdentifiedName());'
    $newAppend = @(
        'snprintf(&tempstr[c], 1024 - c, "%s",',
        "`t`t`t`t`tLegacyArsenal::isPaladinLegacySword(this)",
        "`t`t`t`t`t`t? LegacyArsenal::PALADIN_LEGACY_SWORD_NAME",
        "`t`t`t`t`t`t: items[type].getIdentifiedName());"
    ) -join $lineEnding

    if (-not $descriptionBlock.Contains('LegacyArsenal::PALADIN_LEGACY_SWORD_NAME')) {
        $appendCount = ([regex]::Matches($descriptionBlock, [regex]::Escape($oldAppend))).Count
        if ($appendCount -ne 2) {
            throw "Se esperaban dos anexados del nombre identificado en Item::description(), pero se encontraron $appendCount."
        }
        $descriptionBlock = $descriptionBlock.Replace($oldAppend, $newAppend)
        $text = (
            $text.Substring(0, $descriptionStart) +
            $descriptionBlock +
            $text.Substring($descriptionEnd)
        )
    }

    $getNameAnchor = 'char* Item::getName() const'
    $getNameStart = $text.IndexOf($getNameAnchor, [StringComparison]::Ordinal)
    if ($getNameStart -lt 0) {
        throw "No se pudo localizar Item::getName()."
    }

    $getNameOpenBrace = $text.IndexOf('{', $getNameStart)
    if ($getNameOpenBrace -lt 0) {
        throw "No se encontró la apertura de Item::getName()."
    }

    $customNameBlock = @(
        '',
        "`tif ( LegacyArsenal::isPaladinLegacySword(this) )",
        "`t{",
        "`t`tsnprintf(tempstr, sizeof(tempstr), \"%s\", LegacyArsenal::PALADIN_LEGACY_SWORD_NAME);",
        "`t`treturn tempstr;",
        "`t}"
    ) -join $lineEnding

    $getNameProbeLength = [Math]::Min(600, $text.Length - $getNameStart)
    $getNameProbe = $text.Substring($getNameStart, $getNameProbeLength)
    if (-not $getNameProbe.Contains('LegacyArsenal::isPaladinLegacySword(this)')) {
        $text = $text.Insert($getNameOpenBrace + 1, $customNameBlock)
    }

    try {
        [IO.File]::WriteAllText(
            $sourcePath,
            $text,
            (New-Object Text.UTF8Encoding($false))
        )

        $verification = [IO.File]::ReadAllText($sourcePath)
        if (-not $verification.Contains($includeLine)) {
            throw "No se pudo verificar el include de Legacy Arsenal."
        }
        if (-not $verification.Contains('LegacyArsenal::PALADIN_LEGACY_SWORD_NAME')) {
            throw "No se pudo verificar el nombre visible de Oathblade."
        }
        if (-not $verification.Contains('char* Item::getName() const')) {
            throw "Item::getName() quedó dañado durante la modificación."
        }
    }
    catch {
        [IO.File]::WriteAllBytes($sourcePath, $originalBytes)
        throw
    }

    Invoke-Git @("diff", "--check")

    Write-Host ""
    Write-Host "[OK] Hito M1 aplicado: nombre visible provisional Oathblade." -ForegroundColor Green
    Write-Host ""
    Write-Host "Cambios preparados:" -ForegroundColor Cyan
    & git -C $RepoPath diff --stat
    & git -C $RepoPath diff -- src/items.cpp

    Write-Host ""
    Write-Host "Siguiente comando:" -ForegroundColor Cyan
    Write-Host ".\scripts\windows\build-steamworks.ps1 -Launch"
}
catch {
    Write-Host ""
    Write-Host "================ ERROR ================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
