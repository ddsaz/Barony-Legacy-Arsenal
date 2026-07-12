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

    $sourcePath = Join-Path $RepoPath "src\charclass.cpp"
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

Guarda o descarta esos cambios antes de aplicar el hito M0.
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

    $paladinAnchor = 'else if ( client_classes[player] == CLASS_PALADIN )'
    $paladinStart = $text.IndexOf($paladinAnchor, [StringComparison]::Ordinal)
    if ($paladinStart -lt 0) {
        throw "No se encontró el bloque de carga de la clase Paladín."
    }

    $paladinEndAnchor = 'stats[player]->OLDHP = stats[player]->HP;'
    $paladinEnd = $text.IndexOf($paladinEndAnchor, $paladinStart, [StringComparison]::Ordinal)
    if ($paladinEnd -lt 0) {
        throw "No se pudo determinar el final del bloque de carga del Paladín."
    }

    $paladinLength = $paladinEnd - $paladinStart
    $paladinBlock = $text.Substring($paladinStart, $paladinLength)

    $oldCreation = 'newItem(CLAYMORE_SWORD, SERVICABLE, 0, 1, 0, true, nullptr);'
    $newCreation = 'newItem(CLAYMORE_SWORD, SERVICABLE, 0, 1, LegacyArsenal::PALADIN_LEGACY_SWORD_APPEARANCE, true, nullptr);'

    if ($paladinBlock.Contains($newCreation)) {
        Write-Host "[OK] El hito M0 ya estaba aplicado." -ForegroundColor Green
    }
    else {
        $occurrences = ([regex]::Matches($paladinBlock, [regex]::Escape($oldCreation))).Count
        if ($occurrences -ne 1) {
            throw "Se esperaba una única claymore inicial en el bloque del Paladín, pero se encontraron $occurrences."
        }

        $patchedPaladinBlock = $paladinBlock.Replace($oldCreation, $newCreation)
        $text = (
            $text.Substring(0, $paladinStart) +
            $patchedPaladinBlock +
            $text.Substring($paladinEnd)
        )

        [IO.File]::WriteAllText(
            $sourcePath,
            $text,
            (New-Object Text.UTF8Encoding($false))
        )

        $verification = [IO.File]::ReadAllText($sourcePath)
        if (-not $verification.Contains($includeLine)) {
            [IO.File]::WriteAllBytes($sourcePath, $originalBytes)
            throw "No se pudo verificar el include de Legacy Arsenal."
        }
        if (-not $verification.Contains($newCreation)) {
            [IO.File]::WriteAllBytes($sourcePath, $originalBytes)
            throw "No se pudo verificar la creación de la espada legendaria."
        }

        Write-Host "[OK] Hito M0 aplicado a src\charclass.cpp." -ForegroundColor Green
    }

    Invoke-Git @("diff", "--check")

    Write-Host ""
    Write-Host "Cambios preparados:" -ForegroundColor Cyan
    & git -C $RepoPath diff --stat
    & git -C $RepoPath diff -- src/charclass.cpp

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
