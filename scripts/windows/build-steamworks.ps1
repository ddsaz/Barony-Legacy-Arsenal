#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoPath = "",
    [string]$VcpkgRoot = "",
    [string]$DependenciesRoot = "",
    [string]$SteamworksRoot = "",
    [string]$BaronyDataDir = "",
    [string]$FmodRoot = "",
    [switch]$ResetBuild,
    [switch]$Launch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$BaronyAppId = "371970"
$NfdCommit = "67345b80ebb429ecc2aeda94c478b3bcc5f7888e"

function Resolve-DefaultPaths {
    if ([string]::IsNullOrWhiteSpace($script:RepoPath)) {
        $script:RepoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    }
    if ([string]::IsNullOrWhiteSpace($script:VcpkgRoot)) {
        $script:VcpkgRoot = if ($env:VCPKG_ROOT) {
            $env:VCPKG_ROOT
        } else {
            Join-Path $env:USERPROFILE "source\repos\.tools\vcpkg"
        }
    }
    if ([string]::IsNullOrWhiteSpace($script:DependenciesRoot)) {
        $script:DependenciesRoot = Join-Path $env:USERPROFILE "source\deps"
    }
    if ([string]::IsNullOrWhiteSpace($script:SteamworksRoot)) {
        $script:SteamworksRoot = if ($env:STEAMWORKS_ROOT) {
            $env:STEAMWORKS_ROOT
        } else {
            Join-Path $script:DependenciesRoot "steamworks_sdk"
        }
    }
    if ([string]::IsNullOrWhiteSpace($script:BaronyDataDir)) {
        $script:BaronyDataDir = if ($env:BARONY_DATADIR) {
            $env:BARONY_DATADIR
        } else {
            "K:\SteamLibrary\steamapps\common\Barony"
        }
    }
    if ([string]::IsNullOrWhiteSpace($script:FmodRoot)) {
        $script:FmodRoot = if ($env:FMOD_DIR) {
            $env:FMOD_DIR
        } else {
            "C:\Program Files (x86)\FMOD SoundSystem\FMOD Studio API Windows"
        }
    }

    $script:RepoPath = [IO.Path]::GetFullPath($script:RepoPath)
    $script:VcpkgRoot = [IO.Path]::GetFullPath($script:VcpkgRoot)
    $script:DependenciesRoot = [IO.Path]::GetFullPath($script:DependenciesRoot)
    $script:SteamworksRoot = [IO.Path]::GetFullPath($script:SteamworksRoot)
    $script:BaronyDataDir = [IO.Path]::GetFullPath($script:BaronyDataDir)
    $script:FmodRoot = [IO.Path]::GetFullPath($script:FmodRoot)
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Find-Application {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Candidates = @()
    )

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $command) {
        return [string]$command.Source
    }

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw "No se encontró la aplicación requerida: $Name"
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    Write-Host ""
    Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $rendered = @(
        $output | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.ToString()
            } else {
                [string]$_
            }
        }
    )
    foreach ($line in $rendered) {
        Write-Host $line
    }

    if ($exitCode -ne 0) {
        throw "El comando falló con código ${exitCode}: $FilePath $($Arguments -join ' ')"
    }
}

function Resolve-Steamworks {
    $candidate = $script:SteamworksRoot
    if (Test-Path -LiteralPath (Join-Path $candidate "sdk\public\steam\steam_api.h")) {
        $sdk = Join-Path $candidate "sdk"
    }
    elseif (Test-Path -LiteralPath (Join-Path $candidate "public\steam\steam_api.h")) {
        $sdk = $candidate
    }
    else {
        throw "No se encontró el Steamworks SDK bajo: $candidate"
    }

    $result = [PSCustomObject]@{
        RootForBarony = [string](Split-Path -Parent $sdk)
        Public = [string](Join-Path $sdk "public")
        Library = [string](Join-Path $sdk "redistributable_bin\win64\steam_api64.lib")
        Dll = [string](Join-Path $sdk "redistributable_bin\win64\steam_api64.dll")
    }

    foreach ($path in @(
        (Join-Path $result.Public "steam\steam_api.h"),
        $result.Library,
        $result.Dll
    )) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Steamworks SDK incompleto. Falta: $path"
        }
    }

    return $result
}

function Prepare-Nfd {
    param(
        [Parameter(Mandatory = $true)][string]$GitExe,
        [Parameter(Mandatory = $true)][string]$CMakeExe
    )

    $sourceDir = Join-Path $script:DependenciesRoot "nativefiledialog-src"
    $wrapperDir = Join-Path $script:DependenciesRoot "nativefiledialog-cmake"
    $buildDir = Join-Path $script:DependenciesRoot "nativefiledialog-build"
    $installDir = Join-Path $script:DependenciesRoot "nfd"
    $includeDir = Join-Path $installDir "include\nfd"
    $header = Join-Path $includeDir "nfd.h"
    $library = Join-Path $installDir "lib\nfd.lib"

    if ((-not $ResetBuild) -and
        (Test-Path -LiteralPath $header) -and
        (Test-Path -LiteralPath $library)) {
        Write-Ok "Native File Dialog ya está preparado."
        return [PSCustomObject]@{
            Install = [string]$installDir
            Include = [string]$includeDir
            Library = [string]$library
        }
    }

    New-Item -ItemType Directory -Force -Path $script:DependenciesRoot | Out-Null

    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir ".git"))) {
        if (Test-Path -LiteralPath $sourceDir) {
            Remove-Item -LiteralPath $sourceDir -Recurse -Force
        }
        Invoke-External $GitExe @(
            "clone",
            "https://github.com/mlabbe/nativefiledialog.git",
            $sourceDir
        )
    }

    Invoke-External $GitExe @("-C", $sourceDir, "fetch", "--all", "--tags")
    Invoke-External $GitExe @("-C", $sourceDir, "checkout", "--detach", $NfdCommit)

    New-Item -ItemType Directory -Force -Path $wrapperDir | Out-Null
    $sourceForCMake = $sourceDir.Replace("\", "/")
    $project = @"
cmake_minimum_required(VERSION 3.15)
project(barony_nfd LANGUAGES C CXX)
add_library(nfd STATIC
    "${sourceForCMake}/src/nfd_common.c"
    "${sourceForCMake}/src/nfd_win.cpp"
)
target_include_directories(nfd PUBLIC "${sourceForCMake}/src/include")
target_compile_definitions(nfd PRIVATE _CRT_SECURE_NO_WARNINGS WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(nfd PRIVATE comctl32 ole32 uuid shell32)
set_target_properties(nfd PROPERTIES OUTPUT_NAME "nfd")
install(TARGETS nfd ARCHIVE DESTINATION lib)
install(FILES "${sourceForCMake}/src/include/nfd.h" DESTINATION include/nfd)
"@
    [IO.File]::WriteAllText(
        (Join-Path $wrapperDir "CMakeLists.txt"),
        $project,
        (New-Object System.Text.UTF8Encoding($false))
    )

    if ($ResetBuild -and (Test-Path -LiteralPath $buildDir)) {
        Remove-Item -LiteralPath $buildDir -Recurse -Force
    }

    Invoke-External $CMakeExe @(
        "-S", $wrapperDir,
        "-B", $buildDir,
        "-A", "x64",
        "-Wno-dev",
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
        "-DCMAKE_INSTALL_PREFIX=$installDir"
    )
    Invoke-External $CMakeExe @(
        "--build", $buildDir,
        "--config", "Release",
        "--target", "install",
        "--parallel"
    )

    foreach ($path in @($header, $library)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Native File Dialog no se preparó correctamente. Falta: $path"
        }
    }

    return [PSCustomObject]@{
        Install = [string]$installDir
        Include = [string]$includeDir
        Library = [string]$library
    }
}

function Apply-TemporarySteamStatsCompatibility {
    $sourcePath = Join-Path $script:RepoPath "src\steam_shared.cpp"
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "No existe: $sourcePath"
    }

    $originalBytes = [IO.File]::ReadAllBytes($sourcePath)
    $sourceText = [System.Text.Encoding]::UTF8.GetString($originalBytes)

    $oldCall = 'SteamUserStats\(\)\s*->\s*RequestCurrentStats\s*\(\s*\)'
    $newCall = 'SteamUserStats\(\)\s*->\s*RequestUserStats\s*\(\s*SteamUser\(\)\s*->\s*GetSteamID\(\)\s*\)'

    if ([System.Text.RegularExpressions.Regex]::IsMatch($sourceText, $newCall)) {
        return [PSCustomObject]@{
            Path = [string]$sourcePath
            OriginalBytes = $originalBytes
            Changed = $false
        }
    }

    $returnPattern = '(?m)^(?<indent>[ \t]*)return\s+SteamUserStats\(\)\s*->\s*RequestCurrentStats\s*\(\s*\)\s*;[ \t]*\r?$'
    $match = [System.Text.RegularExpressions.Regex]::Match($sourceText, $returnPattern)
    if (-not $match.Success) {
        throw "No se encontró la llamada Steamworks antigua esperada en steam_shared.cpp."
    }

    $lineEnding = if ($sourceText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $indent = $match.Groups["indent"].Value
    $replacement = (
        $indent + "const SteamAPICall_t request =" + $lineEnding +
        $indent + "    SteamUserStats()->RequestUserStats(SteamUser()->GetSteamID());" + $lineEnding +
        $indent + "return request != k_uAPICallInvalid;"
    )

    $patched = (
        $sourceText.Substring(0, $match.Index) +
        $replacement +
        $sourceText.Substring($match.Index + $match.Length)
    )
    try {
        [IO.File]::WriteAllText(
            $sourcePath,
            $patched,
            (New-Object System.Text.UTF8Encoding($false))
        )

        if (-not [System.Text.RegularExpressions.Regex]::IsMatch($patched, $newCall)) {
            throw "No se pudo verificar la compatibilidad Steamworks temporal."
        }
        if ([System.Text.RegularExpressions.Regex]::IsMatch($patched, $oldCall)) {
            throw "La llamada Steamworks antigua continúa presente."
        }
    }
    catch {
        [IO.File]::WriteAllBytes($sourcePath, $originalBytes)
        throw
    }

    Write-Ok "Compatibilidad Steamworks aplicada temporalmente."
    return [PSCustomObject]@{
        Path = [string]$sourcePath
        OriginalBytes = $originalBytes
        Changed = $true
    }
}

function Restore-TemporarySource {
    param($PatchState)

    if (($null -ne $PatchState) -and $PatchState.Changed) {
        [IO.File]::WriteAllBytes($PatchState.Path, $PatchState.OriginalBytes)
        Write-Ok "steam_shared.cpp restaurado; el árbol de trabajo queda limpio."
    }
}

function Main {
    Resolve-DefaultPaths

    Write-Host "Barony Legacy Arsenal - Steamworks baseline v1" -ForegroundColor White

    $gitExe = Find-Application "git" @(
        "$env:ProgramFiles\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )
    $cmakeExe = Find-Application "cmake" @(
        "$env:ProgramFiles\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "$env:ProgramFiles\CMake\bin\cmake.exe"
    )

    $toolchain = Join-Path $script:VcpkgRoot "scripts\buildsystems\vcpkg.cmake"
    $vcpkgInstalled = Join-Path $script:VcpkgRoot "installed\x64-windows"
    $glewInclude = Join-Path $vcpkgInstalled "include"
    $glewHeader = Join-Path $glewInclude "GL\glew.h"
    $glewLibrary = Join-Path $vcpkgInstalled "lib\glew32.lib"
    $vcpkgBin = Join-Path $vcpkgInstalled "bin"
    $compatHeader = Join-Path $script:RepoPath "src\windows_msvc_compat.hpp"

    $fmodInclude = Join-Path $script:FmodRoot "api\core\inc"
    $fmodLibrary = Join-Path $script:FmodRoot "api\core\lib\x64\fmod_vc.lib"
    $fmodDll = Join-Path $script:FmodRoot "api\core\lib\x64\fmod.dll"

    foreach ($path in @(
        $script:RepoPath,
        $script:BaronyDataDir,
        $toolchain,
        $glewHeader,
        $glewLibrary,
        $compatHeader,
        (Join-Path $fmodInclude "fmod.hpp"),
        $fmodLibrary,
        $fmodDll
    )) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Falta una ruta requerida: $path"
        }
    }

    Write-Step "Validando Steamworks y Native File Dialog"
    $steamworks = Resolve-Steamworks
    $nfdResults = @(Prepare-Nfd $gitExe $cmakeExe)
    $nfd = $nfdResults |
        Where-Object { $_ -and $_.PSObject.Properties["Library"] } |
        Select-Object -Last 1
    if ($null -eq $nfd) {
        throw "Native File Dialog no devolvió rutas válidas."
    }

    $patchState = $null
    try {
        Write-Step "Aplicando compatibilidad temporal del Steamworks SDK"
        $patchState = Apply-TemporarySteamStatsCompatibility

        $env:STEAMWORKS_ROOT = $steamworks.RootForBarony
        $env:STEAMWORKS_ENABLED = "1"
        $env:NFD_DIR = $nfd.Install
        $env:EDITOR_ENABLED = "0"
        $env:GAME_ENABLED = "1"
        $env:BARONY_DATADIR = $script:BaronyDataDir
        $env:BARONY_WIN32_LIBRARIES = $vcpkgInstalled
        $env:FMOD_DIR = $script:FmodRoot

        $buildDir = Join-Path $script:RepoPath "build\windows-steam-x64"
        if ($ResetBuild -and (Test-Path -LiteralPath $buildDir)) {
            Write-Step "Eliminando build anterior"
            Remove-Item -LiteralPath $buildDir -Recurse -Force
        }

        $toCMake = {
            param([string]$Path)
            return $Path.Replace("\", "/")
        }

        $cxxFlags = "/EHsc /I$(& $toCMake $glewInclude) /FI$(& $toCMake $compatHeader)"
        $linkerFlags = "$(& $toCMake $glewLibrary) comctl32.lib ole32.lib uuid.lib shell32.lib"

        Write-Step "Configurando CMake"
        Invoke-External $cmakeExe @(
            "-S", $script:RepoPath,
            "-B", $buildDir,
            "-A", "x64",
            "-Wno-dev",
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
            "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
            "-DVCPKG_TARGET_TRIPLET=x64-windows",
            "-DCMAKE_PREFIX_PATH=$vcpkgInstalled",
            "-DCMAKE_CXX_STANDARD=17",
            "-DCMAKE_CXX_STANDARD_REQUIRED=ON",
            "-DCMAKE_CXX_EXTENSIONS=OFF",
            "-DCMAKE_CXX_FLAGS=$cxxFlags",
            "-DCMAKE_C_FLAGS=/I$(& $toCMake $glewInclude)",
            "-DCMAKE_EXE_LINKER_FLAGS=$linkerFlags",
            "-DFMOD_ENABLED=ON",
            "-DFMOD_INCLUDE_DIR=$(& $toCMake $fmodInclude)",
            "-DFMOD_LIBRARY=$(& $toCMake $fmodLibrary)",
            "-DOPENAL_ENABLED=OFF",
            "-DSTEAMWORKS_ENABLED=1",
            "-DSTEAMWORKS_INCLUDE_DIR=$(& $toCMake $steamworks.Public)",
            "-DSTEAMWORKS_LIBRARY=$(& $toCMake $steamworks.Library)",
            "-DSTEAMWORKS_LIBRARIES=$(& $toCMake $steamworks.Library)",
            "-DNFD_INCLUDE_DIR=$(& $toCMake $nfd.Include)",
            "-DNFD_LIBRARY=$(& $toCMake $nfd.Library)",
            "-DNFD_LIBRARIES=$(& $toCMake $nfd.Library)",
            "-DEOS_ENABLED=0",
            "-DPLAYFAB_ENABLED=0",
            "-DTHEORAPLAYER_ENABLED=0",
            "-DCURL_ENABLED=0",
            "-DOPUS_ENABLED=0"
        )

        Write-Step "Compilando barony"
        Invoke-External $cmakeExe @(
            "--build", $buildDir,
            "--config", "Release",
            "--target", "barony",
            "--parallel"
        )

        $builtExe = Get-ChildItem -LiteralPath $buildDir -Filter "barony.exe" -File -Recurse |
            Sort-Object @{ Expression = { if ($_.FullName -match "\\Release\\") { 0 } else { 1 } } }, FullName |
            Select-Object -First 1
        if (($null -eq $builtExe) -or ($builtExe.Length -le 0)) {
            throw "No se encontró un barony.exe válido."
        }

        Write-Step "Preparando ejecución"
        $stage = Join-Path $script:BaronyDataDir "LegacyArsenal"
        New-Item -ItemType Directory -Force -Path $stage | Out-Null

        $stagedExe = Join-Path $stage "barony_legacy.exe"
        Copy-Item -LiteralPath $builtExe.FullName -Destination $stagedExe -Force

        if (Test-Path -LiteralPath $vcpkgBin) {
            Get-ChildItem -LiteralPath $vcpkgBin -Filter "*.dll" -File |
                ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $stage -Force
                }
        }
        Copy-Item -LiteralPath $fmodDll -Destination $stage -Force
        Copy-Item -LiteralPath $steamworks.Dll -Destination $stage -Force

        foreach ($appIdPath in @(
            (Join-Path $script:BaronyDataDir "steam_appid.txt"),
            (Join-Path $stage "steam_appid.txt")
        )) {
            [IO.File]::WriteAllText(
                $appIdPath,
                $BaronyAppId + [Environment]::NewLine,
                (New-Object System.Text.ASCIIEncoding)
            )
        }

        $launcher = Join-Path $stage "Launch-Barony-Legacy-Steam.ps1"
        $launcherText = @"
`$ErrorActionPreference = "Stop"
`$exe = Join-Path `$PSScriptRoot "barony_legacy.exe"
Start-Process -FilePath `$exe -WorkingDirectory "$($script:BaronyDataDir)"
"@
        [IO.File]::WriteAllText(
            $launcher,
            $launcherText,
            (New-Object System.Text.UTF8Encoding($true))
        )

        foreach ($path in @(
            $stagedExe,
            (Join-Path $stage "steam_api64.dll"),
            (Join-Path $stage "fmod.dll"),
            (Join-Path $stage "steam_appid.txt"),
            $launcher
        )) {
            if (-not (Test-Path -LiteralPath $path)) {
                throw "Falta un archivo de ejecución: $path"
            }
        }

        Write-Host ""
        Write-Host "================ OK ================" -ForegroundColor Green
        Write-Host "Ejecutable: $stagedExe"
        Write-Host "Launcher:   $launcher"

        if ($Launch) {
            if ($null -eq (Get-Process -Name "steam" -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                throw "Steam no está abierto."
            }
            & $launcher
        }
    }
    finally {
        Restore-TemporarySource $patchState
    }
}

try {
    Main
}
catch {
    Write-Host ""
    Write-Host "================ ERROR ================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
