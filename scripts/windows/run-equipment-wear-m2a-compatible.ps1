#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$temporaryPath = $null

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
        throw "No se pudo localizar la funcion Replace-Exact del script M2A."
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

    # [ref] sobre una propiedad (por ejemplo [ref]$main.Text) no conserva de
    # forma fiable la asignacion en Windows PowerShell 5.1. Modificamos
    # directamente los objetos de estado usados por el script original.
    $candidateStates = @($net, $interface, $menu, $main) | Where-Object {
        $_ -ne $null -and $_.PSObject.Properties.Name -contains 'Text'
    }

    $exactCounts = @()
    $totalExact = 0
    foreach ($state in $candidateStates) {
        $count = ([regex]::Matches($state.Text, [regex]::Escape($Old))).Count
        $exactCounts += $count
        $totalExact += $count
    }

    if ($totalExact -eq $ExpectedCount) {
        for ($i = 0; $i -lt $candidateStates.Count; $i++) {
            if ($exactCounts[$i] -gt 0) {
                $candidateStates[$i].Text = $candidateStates[$i].Text.Replace($Old, $New)
            }
        }
        return
    }

    # The upstream source mixes tabs and spaces, and equivalent blocks can use
    # different indentation depths. Build a whitespace-tolerant pattern.
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
    $tolerantCounts = @()
    $totalTolerant = 0
    foreach ($state in $candidateStates) {
        $count = $regex.Matches($state.Text).Count
        $tolerantCounts += $count
        $totalTolerant += $count
    }

    if ($totalTolerant -ne $ExpectedCount) {
        throw "${Label}: se esperaban $ExpectedCount coincidencias; exactas=$totalExact, tolerantes=$totalTolerant."
    }

    $evaluator = [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $New
    }

    for ($i = 0; $i -lt $candidateStates.Count; $i++) {
        if ($tolerantCounts[$i] -gt 0) {
            $candidateStates[$i].Text = $regex.Replace(
                $candidateStates[$i].Text,
                $evaluator,
                $tolerantCounts[$i]
            )
        }
    }
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
            "Linea $($_.Extent.StartLineNumber), columna $($_.Extent.StartColumnNumber): $($_.Message)"
        }) -join [Environment]::NewLine
        throw "La copia compatible no supera el parser:`n$details"
    }

    Write-Host "[OK] Ejecutando M2A con compatibilidad para PowerShell 5.1." -ForegroundColor Green
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
