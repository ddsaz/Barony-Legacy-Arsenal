#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        $RepoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    }
    else {
        $RepoPath = [IO.Path]::GetFullPath($RepoPath)
    }

    $targetPath = Join-Path $RepoPath "scripts\windows\apply-equipment-wear-m2a.ps1"
    if (-not (Test-Path -LiteralPath $targetPath)) {
        throw "No existe el script M2A: $targetPath"
    }

    $text = [IO.File]::ReadAllText($targetPath)
    $broken = 'throw "$Label: se esperaban $ExpectedCount coincidencias, pero se encontraron $count."'
    $fixed = 'throw "${Label}: se esperaban $ExpectedCount coincidencias, pero se encontraron $count."'

    $brokenCount = ([regex]::Matches($text, [regex]::Escape($broken))).Count
    $fixedCount = ([regex]::Matches($text, [regex]::Escape($fixed))).Count

    if ($brokenCount -eq 1 -and $fixedCount -eq 0) {
        $text = $text.Replace($broken, $fixed)
        [IO.File]::WriteAllText(
            $targetPath,
            $text,
            (New-Object Text.UTF8Encoding($false))
        )
        Write-Host "[OK] Referencia de variable corregida: `${Label}:" -ForegroundColor Green
    }
    elseif ($brokenCount -eq 0 -and $fixedCount -eq 1) {
        Write-Host "[OK] El parser fix ya estaba aplicado." -ForegroundColor Green
    }
    else {
        throw "Estado inesperado: broken=$brokenCount, fixed=$fixedCount. No se modifica el archivo."
    }

    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $targetPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object {
            "Línea $($_.Extent.StartLineNumber), columna $($_.Extent.StartColumnNumber): $($_.Message)"
        }) -join [Environment]::NewLine
        throw "El script continúa teniendo errores de sintaxis:`n$details"
    }

    Write-Host "[OK] apply-equipment-wear-m2a.ps1 supera el parser de PowerShell." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "================ ERROR ================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
