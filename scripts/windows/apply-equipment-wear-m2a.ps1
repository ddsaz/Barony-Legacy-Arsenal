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

function Replace-Exact {
    param(
        [Parameter(Mandatory = $true)][ref]$Text,
        [Parameter(Mandatory = $true)][string]$Old,
        [Parameter(Mandatory = $true)][string]$New,
        [Parameter(Mandatory = $true)][int]$ExpectedCount,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $count = ([regex]::Matches($Text.Value, [regex]::Escape($Old))).Count
    if ($count -ne $ExpectedCount) {
        throw "$Label: se esperaban $ExpectedCount coincidencias, pero se encontraron $count."
    }

    $Text.Value = $Text.Value.Replace($Old, $New)
}

function Read-SourceFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [PSCustomObject]@{
        Path = $Path
        OriginalBytes = [IO.File]::ReadAllBytes($Path)
        Text = [IO.File]::ReadAllText($Path)
    }
}

function Write-SourceFile {
    param($State)

    [IO.File]::WriteAllText(
        $State.Path,
        $State.Text,
        (New-Object Text.UTF8Encoding($false))
    )
}

try {
    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        $RepoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    }
    else {
        $RepoPath = [IO.Path]::GetFullPath($RepoPath)
    }
    $script:RepoPath = $RepoPath

    $branch = (& git -C $RepoPath branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo determinar la rama actual."
    }
    if ($branch -ne "feature/paladin-legacy-sword") {
        throw "La rama actual es '$branch'. Cambia primero a feature/paladin-legacy-sword."
    }

    & git -C $RepoPath diff --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Hay cambios rastreados sin confirmar. Confírmalos o restáuralos antes de aplicar M2A."
    }
    & git -C $RepoPath diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Hay cambios preparados sin confirmar. Confírmalos antes de aplicar M2A."
    }

    $paths = @(
        (Join-Path $RepoPath "src\net.hpp"),
        (Join-Path $RepoPath "src\interface\interface.cpp"),
        (Join-Path $RepoPath "src\menu.cpp"),
        (Join-Path $RepoPath "src\ui\MainMenu.cpp")
    )

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "No existe la ruta requerida: $path"
        }
    }

    $states = @()
    foreach ($path in $paths) {
        $states += Read-SourceFile -Path $path
    }

    $net = $states[0]
    $interface = $states[1]
    $menu = $states[2]
    $main = $states[3]

    $nl = if ($main.Text.Contains("`r`n")) { "`r`n" } else { "`n" }

    # net.hpp: reserve bit 10. NUM_SERVER_FLAGS remains 10 deliberately because
    # it also controls the vanilla lobby-browser filter layout.
    Replace-Exact ([ref]$net.Text) `
        ('const Uint32 SV_FLAG_ASSIST_ITEMS = 1 << 9;' + $nl +
         'const Uint32 NUM_SERVER_FLAGS =  10;') `
        ('const Uint32 SV_FLAG_ASSIST_ITEMS = 1 << 9;' + $nl +
         'const Uint32 SV_FLAG_EQUIPMENT_WEAR = 1 << 10;' + $nl +
         '// Vanilla lobby-browser filters cover the original ten flags.' + $nl +
         'const Uint32 NUM_SERVER_FLAGS =  10;') `
        1 "Declaración del nuevo server flag"

    # Default and tutorial behaviour: equipment wear is enabled by default.
    Replace-Exact ([ref]$interface.Text) `
        'Uint32 svFlags = 30;' `
        'Uint32 svFlags = 30 | SV_FLAG_EQUIPMENT_WEAR;' `
        1 "Valor predeterminado de svFlags"

    $menuNl = if ($menu.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    Replace-Exact ([ref]$menu.Text) `
        ('svFlags |= SV_FLAG_TRAPS;' + $menuNl) `
        ('svFlags |= SV_FLAG_TRAPS;' + $menuNl +
         "`t`tsvFlags |= SV_FLAG_EQUIPMENT_WEAR;" + $menuNl) `
        1 "Configuración del tutorial"

    # AllSettings data model and config persistence.
    Replace-Exact ([ref]$main.Text) `
        ("`t`tbool random_traps_enabled = true;" + $nl +
         "`t`tbool extra_life_enabled = false;") `
        ("`t`tbool random_traps_enabled = true;" + $nl +
         "`t`tbool equipment_wear_enabled = true;" + $nl +
         "`t`tbool extra_life_enabled = false;") `
        1 "Campo AllSettings"

    Replace-Exact ([ref]$main.Text) `
        ("`t`t    svFlags = random_traps_enabled ? svFlags | SV_FLAG_TRAPS : svFlags & ~(SV_FLAG_TRAPS);" + $nl +
         "`t`t    svFlags = /*extra_life_enabled") `
        ("`t`t    svFlags = random_traps_enabled ? svFlags | SV_FLAG_TRAPS : svFlags & ~(SV_FLAG_TRAPS);" + $nl +
         "`t`t    svFlags = equipment_wear_enabled ? svFlags | SV_FLAG_EQUIPMENT_WEAR : svFlags & ~(SV_FLAG_EQUIPMENT_WEAR);" + $nl +
         "`t`t    svFlags = /*extra_life_enabled") `
        1 "Aplicación desde AllSettings"

    Replace-Exact ([ref]$main.Text) `
        ("`t`tsettings.random_traps_enabled = svFlags & SV_FLAG_TRAPS;" + $nl +
         "`t`tsettings.extra_life_enabled") `
        ("`t`tsettings.random_traps_enabled = svFlags & SV_FLAG_TRAPS;" + $nl +
         "`t`tsettings.equipment_wear_enabled = svFlags & SV_FLAG_EQUIPMENT_WEAR;" + $nl +
         "`t`tsettings.extra_life_enabled") `
        1 "Carga de AllSettings"

    Replace-Exact ([ref]$main.Text) `
        ("`tbool AllSettings::serialize(FileInterface* file) {" + $nl +
         "`t    int version = 25;") `
        ("`tbool AllSettings::serialize(FileInterface* file) {" + $nl +
         "`t    int version = 26;") `
        1 "Versión de configuración"

    Replace-Exact ([ref]$main.Text) `
        ("`t`tfile->property(`"random_traps_enabled`", random_traps_enabled);" + $nl +
         "`t`tbool no = false;") `
        ("`t`tfile->property(`"random_traps_enabled`", random_traps_enabled);" + $nl +
         "`t`tfile->propertyVersion(`"equipment_wear_enabled`", version >= 26, equipment_wear_enabled);" + $nl +
         "`t`tbool no = false;") `
        1 "Persistencia de equipment_wear_enabled"

    # Standard Game Settings page.
    Replace-Exact ([ref]$main.Text) `
        ("`t`t`tallSettings.random_traps_enabled = svFlags & SV_FLAG_TRAPS;" + $nl +
         "`t`t`tallSettings.extra_life_enabled") `
        ("`t`t`tallSettings.random_traps_enabled = svFlags & SV_FLAG_TRAPS;" + $nl +
         "`t`t`tallSettings.equipment_wear_enabled = svFlags & SV_FLAG_EQUIPMENT_WEAR;" + $nl +
         "`t`t`tallSettings.extra_life_enabled") `
        2 "Montaje de opciones desde svFlags"

    Replace-Exact ([ref]$main.Text) `
        ("`t`ty += settingsAddBooleanOption(*settings_subwindow, y, `"random_traps`", Language::get(5255), Language::get(5256)," + $nl +
         "`t`t`tallSettings.random_traps_enabled, [](Button& button){soundToggleSetting(button); allSettings.random_traps_enabled = button.isPressed();});" + $nl +
         "`t`ty += settingsAddBooleanOption(*settings_subwindow, y, `"friendly_fire`"") `
        ("`t`ty += settingsAddBooleanOption(*settings_subwindow, y, `"random_traps`", Language::get(5255), Language::get(5256)," + $nl +
         "`t`t`tallSettings.random_traps_enabled, [](Button& button){soundToggleSetting(button); allSettings.random_traps_enabled = button.isPressed();});" + $nl +
         "`t`ty += settingsAddBooleanOption(*settings_subwindow, y, `"equipment_wear`", `"Equipment Wear`"," + $nl +
         "`t`t`t`"When enabled, weapons, armor, shields and reusable tools can lose condition through normal use.`"," + $nl +
         "`t`t`tallSettings.equipment_wear_enabled, [](Button& button){soundToggleSetting(button); allSettings.equipment_wear_enabled = button.isPressed();});" + $nl +
         "`t`ty += settingsAddBooleanOption(*settings_subwindow, y, `"friendly_fire`"") `
        1 "Opción visible en Game Settings"

    Replace-Exact ([ref]$main.Text) `
        ("`t`t`t`t`t{`"setting_random_traps_button`", SV_FLAG_TRAPS}," + $nl +
         "`t`t`t`t`t{`"setting_friendly_fire_button`"") `
        ("`t`t`t`t`t{`"setting_random_traps_button`", SV_FLAG_TRAPS}," + $nl +
         "`t`t`t`t`t{`"setting_equipment_wear_button`", SV_FLAG_EQUIPMENT_WEAR}," + $nl +
         "`t`t`t`t`t{`"setting_friendly_fire_button`"") `
        1 "Bloqueo del botón en clientes"

    Replace-Exact ([ref]$main.Text) `
        ("`t`t`t`t`t`tcase SV_FLAG_TRAPS: options[`"setting_random_traps_button`"] = SV_FLAG_TRAPS; break;" + $nl +
         "`t`t`t`t`t`tcase SV_FLAG_FRIENDLYFIRE:") `
        ("`t`t`t`t`t`tcase SV_FLAG_TRAPS: options[`"setting_random_traps_button`"] = SV_FLAG_TRAPS; break;" + $nl +
         "`t`t`t`t`t`tcase SV_FLAG_EQUIPMENT_WEAR: options[`"setting_equipment_wear_button`"] = SV_FLAG_EQUIPMENT_WEAR; break;" + $nl +
         "`t`t`t`t`t`tcase SV_FLAG_FRIENDLYFIRE:") `
        1 "Mapa de flags bloqueados"

    # Character creation custom-difficulty card.
    Replace-Exact ([ref]$main.Text) `
        'auto card = initCharacterCard(index, 664);' `
        'auto card = initCharacterCard(index, 714);' `
        1 "Altura del panel de dificultad"

    Replace-Exact ([ref]$main.Text) `
        ("`t`t`tallSettings.random_traps_enabled = lobbyWindowSvFlags & SV_FLAG_TRAPS;" + $nl +
         "`t`t`tallSettings.extra_life_enabled") `
        ("`t`t`tallSettings.random_traps_enabled = lobbyWindowSvFlags & SV_FLAG_TRAPS;" + $nl +
         "`t`t`tallSettings.equipment_wear_enabled = lobbyWindowSvFlags & SV_FLAG_EQUIPMENT_WEAR;" + $nl +
         "`t`t`tallSettings.extra_life_enabled") `
        1 "Montaje del cliente desde lobbyWindowSvFlags"

    Replace-Exact ([ref]$main.Text) `
        ("`t`t`t    svFlags = allSettings.random_traps_enabled ? svFlags | SV_FLAG_TRAPS : svFlags & ~(SV_FLAG_TRAPS);" + $nl +
         "`t`t`t    svFlags = /*allSettings.extra_life_enabled") `
        ("`t`t`t    svFlags = allSettings.random_traps_enabled ? svFlags | SV_FLAG_TRAPS : svFlags & ~(SV_FLAG_TRAPS);" + $nl +
         "`t`t`t    svFlags = allSettings.equipment_wear_enabled ? svFlags | SV_FLAG_EQUIPMENT_WEAR : svFlags & ~(SV_FLAG_EQUIPMENT_WEAR);" + $nl +
         "`t`t`t    svFlags = /*allSettings.extra_life_enabled") `
        1 "Confirmación desde el panel personalizado"

    Replace-Exact ([ref]$main.Text) `
        ("`t`t`t    svFlags = allSettings.random_traps_enabled ? svFlags | SV_FLAG_TRAPS : svFlags & ~(SV_FLAG_TRAPS);" + $nl +
         "`t`t`t    svFlags = allSettings.extra_life_enabled") `
        ("`t`t`t    svFlags = allSettings.random_traps_enabled ? svFlags | SV_FLAG_TRAPS : svFlags & ~(SV_FLAG_TRAPS);" + $nl +
         "`t`t`t    svFlags = allSettings.equipment_wear_enabled ? svFlags | SV_FLAG_EQUIPMENT_WEAR : svFlags & ~(SV_FLAG_EQUIPMENT_WEAR);" + $nl +
         "`t`t`t    svFlags = allSettings.extra_life_enabled") `
        1 "Selección de dificultad personalizada"

    Replace-Exact ([ref]$main.Text) `
        ("`t`t`tLanguage::get(5385), // hardcore difficulty" + $nl +
         "#ifndef NINTENDO") `
        ("`t`t`tLanguage::get(5385), // hardcore difficulty" + $nl +
         "`t`t`t`"Disable Equipment Wear`"," + $nl +
         "#ifndef NINTENDO") `
        1 "Etiqueta del toggle en el lobby"

    $oldCase8 = @(
        "`t`t`tcase 8:",
        "`t`t`t`tif ( gameModeManager.isServerflagDisabledForCurrentMode(SV_FLAG_CHEATS) )",
        "`t`t`t`t{",
        "`t`t`t`t`tlabel->setColor(makeColor(128, 128, 128, 255));",
        "`t`t`t`t}",
        "`t`t`t`tsetting->setPressed(allSettings.cheats_enabled);",
        "`t`t`t`tsetting->setCallback([](Button& button){",
        "`t`t`t`t`tif ( gameModeManager.isServerflagDisabledForCurrentMode(SV_FLAG_CHEATS) )",
        "`t`t`t`t`t{",
        "`t`t`t`t`t`tsoundError();",
        "`t`t`t`t`t`tbutton.setPressed(allSettings.cheats_enabled);",
        "`t`t`t`t`t`treturn;",
        "`t`t`t`t`t}",
        "`t`t`t`t`tsoundCheckmark(); allSettings.cheats_enabled = button.isPressed();});",
        "`t`t`t`tbreak;"
    ) -join $nl

    $newCase8 = @(
        "`t`t`tcase 8:",
        "`t`t`t`tsetting->setPressed(!allSettings.equipment_wear_enabled);",
        "`t`t`t`tsetting->setCallback([](Button& button){",
        "`t`t`t`t`tsoundCheckmark(); allSettings.equipment_wear_enabled = !button.isPressed();});",
        "`t`t`t`tbreak;",
        "#ifndef NINTENDO",
        "`t`t`tcase 9:",
        "`t`t`t`tif ( gameModeManager.isServerflagDisabledForCurrentMode(SV_FLAG_CHEATS) )",
        "`t`t`t`t{",
        "`t`t`t`t`tlabel->setColor(makeColor(128, 128, 128, 255));",
        "`t`t`t`t}",
        "`t`t`t`tsetting->setPressed(allSettings.cheats_enabled);",
        "`t`t`t`tsetting->setCallback([](Button& button){",
        "`t`t`t`t`tif ( gameModeManager.isServerflagDisabledForCurrentMode(SV_FLAG_CHEATS) )",
        "`t`t`t`t`t{",
        "`t`t`t`t`t`tsoundError();",
        "`t`t`t`t`t`tbutton.setPressed(allSettings.cheats_enabled);",
        "`t`t`t`t`t`treturn;",
        "`t`t`t`t`t}",
        "`t`t`t`t`tsoundCheckmark(); allSettings.cheats_enabled = button.isPressed();});",
        "`t`t`t`tbreak;",
        "#endif"
    ) -join $nl

    Replace-Exact ([ref]$main.Text) $oldCase8 $newCase8 1 "Callbacks del nuevo toggle"

    Replace-Exact ([ref]$main.Text) `
        ("`t`tachievements->setSize(SDL_Rect{54, 526, 214, 50});") `
        ("`t`tachievements->setSize(SDL_Rect{54, 576, 214, 50});") `
        1 "Posición del estado de logros"

    $oldTickCases = @(
        "                    case 8:",
        "                        button->setPressed((lobbyWindowSvFlags & SV_FLAG_CHEATS));",
        "                        break;"
    ) -join $nl
    $newTickCases = @(
        "                    case 8:",
        "                        button->setPressed(!(lobbyWindowSvFlags & SV_FLAG_EQUIPMENT_WEAR));",
        "                        break;",
        "                    case 9:",
        "                        button->setPressed((lobbyWindowSvFlags & SV_FLAG_CHEATS));",
        "                        break;"
    ) -join $nl
    Replace-Exact ([ref]$main.Text) $oldTickCases $newTickCases 1 "Actualización visual del cliente"

    # Difficulty presets: vanilla wear remains enabled unless the host selects
    # Custom and explicitly disables it.
    $presetPairs = @(
        @(
            'svFlags = SV_FLAG_CLASSIC | SV_FLAG_KEEPINVENTORY | SV_FLAG_LIFESAVING;',
            'svFlags = SV_FLAG_CLASSIC | SV_FLAG_KEEPINVENTORY | SV_FLAG_LIFESAVING | SV_FLAG_EQUIPMENT_WEAR;'
        ),
        @(
            'svFlags == (SV_FLAG_CLASSIC | SV_FLAG_KEEPINVENTORY | SV_FLAG_LIFESAVING)',
            'svFlags == (SV_FLAG_CLASSIC | SV_FLAG_KEEPINVENTORY | SV_FLAG_LIFESAVING | SV_FLAG_EQUIPMENT_WEAR)'
        ),
        @(
            'svFlags = SV_FLAG_FRIENDLYFIRE | SV_FLAG_KEEPINVENTORY | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS;',
            'svFlags = SV_FLAG_FRIENDLYFIRE | SV_FLAG_KEEPINVENTORY | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS | SV_FLAG_EQUIPMENT_WEAR;'
        ),
        @(
            'svFlags == (SV_FLAG_FRIENDLYFIRE | SV_FLAG_KEEPINVENTORY | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS)',
            'svFlags == (SV_FLAG_FRIENDLYFIRE | SV_FLAG_KEEPINVENTORY | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS | SV_FLAG_EQUIPMENT_WEAR)'
        ),
        @(
            'svFlags = SV_FLAG_HARDCORE | SV_FLAG_FRIENDLYFIRE | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS;',
            'svFlags = SV_FLAG_HARDCORE | SV_FLAG_FRIENDLYFIRE | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS | SV_FLAG_EQUIPMENT_WEAR;'
        ),
        @(
            'svFlags == (SV_FLAG_HARDCORE | SV_FLAG_FRIENDLYFIRE | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS)',
            'svFlags == (SV_FLAG_HARDCORE | SV_FLAG_FRIENDLYFIRE | SV_FLAG_HUNGER | SV_FLAG_MINOTAURS | SV_FLAG_TRAPS | SV_FLAG_EQUIPMENT_WEAR)'
        )
    )
    foreach ($pair in $presetPairs) {
        Replace-Exact ([ref]$main.Text) $pair[0] $pair[1] 1 "Preset de dificultad"
    }

    $requiredMarkers = @(
        "SV_FLAG_EQUIPMENT_WEAR",
        "equipment_wear_enabled",
        "setting_equipment_wear_button",
        "Disable Equipment Wear",
        "Equipment Wear",
        'propertyVersion("equipment_wear_enabled", version >= 26'
    )
    foreach ($marker in $requiredMarkers) {
        if (-not (
            $net.Text.Contains($marker) -or
            $interface.Text.Contains($marker) -or
            $menu.Text.Contains($marker) -or
            $main.Text.Contains($marker)
        )) {
            throw "No se pudo verificar el marcador final: $marker"
        }
    }

    try {
        foreach ($state in $states) {
            Write-SourceFile -State $state
        }

        Invoke-Git @("diff", "--check")
    }
    catch {
        foreach ($state in $states) {
            [IO.File]::WriteAllBytes($state.Path, $state.OriginalBytes)
        }
        throw
    }

    Write-Host ""
    Write-Host "[OK] M2A aplicado: toggle global de desgaste y sincronización por svFlags." -ForegroundColor Green
    Write-Host ""
    Write-Host "Todavía no se ha desactivado ningún punto de desgaste; eso pertenece a M2B." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Cambios preparados:" -ForegroundColor Cyan
    & git -C $RepoPath diff --stat
    & git -C $RepoPath diff -- src/net.hpp src/interface/interface.cpp src/menu.cpp src/ui/MainMenu.cpp
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
