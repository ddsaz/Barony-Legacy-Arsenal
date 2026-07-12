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

    $sourcePath = Join-Path $RepoPath "scripts\windows\apply-equipment-wear-m2a.ps1"
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "No existe el script M2A: $sourcePath"
    }

    $text = [IO.File]::ReadAllText($sourcePath)

    # PowerShell 5.1 parses "$Label:" as a scoped variable reference.
    $text = $text.Replace(
        'throw "$Label: se esperaban $ExpectedCount coincidencias, pero se encontraron $count."',
        'throw "${Label}: se esperaban $ExpectedCount coincidencias, pero se encontraron $count."'
    )

    $functionStart = $text.IndexOf("function Replace-Exact {", [StringComparison]::Ordinal)
    $nextFunction = $text.IndexOf("function Read-SourceFile {", $functionStart, [StringComparison]::Ordinal)
    if ($functionStart -lt 0 -or $nextFunction -lt 0) {
        throw "No se pudo localizar la función Replace-Exact del script M2A."
    }

    $replacementFunction = @'
function Replace-Exact {
    param(
        [Parameter(Mandatory = $true)][ref]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][int]$ExpectedCount,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $exactCount = ([regex]::Matches($Text.Value, [regex]::Escape($Old))).Count
    if ($exactCount -eq $ExpectedCount) {
        $Text.Value = $Text.Value.Replace($Old, $New)
        return
    }

    # The upstream source mixes tabs and spaces, and some equivalent blocks use
    # different indentation depths. Always try the whitespace-tolerant pattern
    # before reporting a mismatch, even if a subset matched exactly.
    $patternBuilder = New-Object Text.StringBuilder
    $insideHorizontalWhitespace = $false
    foreach ($character in $Old.ToCharArray()) {
        if ($character -eq ' ' -or $character -eq "`t") {
            if (-not $insideHorizontalWhitespace) {
                [void]$patternBuilder.Append('[ \t]+')
                $insideHorizontalWhitespace = $true
            }
            continue
        }

        $insideHorizontalWhitespace = $false
        [void]$patternBuilder.Append([regex]::Escape([string]$character))
    }

    $pattern = $patternBuilder.ToString()
    $regex = New-Object Text.RegularExpressions.Regex($pattern)
    $matches = $regex.Matches($Text.Value)
    if ($matches.Count -ne $ExpectedCount) {
        throw "${Label}: se esperaban $ExpectedCount coincidencias; exactas=$exactCount, tolerantes=$($matches.Count)."
    }

    $evaluator = [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $New
    }
    $Text.Value = $regex.Replace($Text.Value, $evaluator, $ExpectedCount)
}

'@

    $text = (
        $text.Substring(0, $functionStart) +
        $replacementFunction +
        $text.Substring($nextFunction)
    )

    $temporaryPath = Join-Path $env:TEMP "apply-equipment-wear-m2a-compatible-$PID.ps1"
    [IO.File]::WriteAllText(
        $temporaryPath,
        $text,
        (New-Object Text.UTF8Encoding($false))
    )

    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $temporaryPath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object {
            "Línea $($_.Extent.StartLineNumber), columna $($_.Extent.StartColumnNumber): $($_.Message)"
        }) -join [Environment]::NewLine
        throw "La copia compatible no supera el parser:`n$details"
    }

    Write-Host "[OK] Ejecutando M2A con comparación tolerante a tabulaciones y espacios." -ForegroundColor Green
    & $temporaryPath -RepoPath $RepoPath
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
catch {
    Write-Host ""
    Write-Host "================ ERROR ================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}
