# M2A — Global equipment wear toggle

M2A adds a host-controlled, synchronized server option for normal equipment wear.

## New server flag

```cpp
SV_FLAG_EQUIPMENT_WEAR = 1 << 10
```

The flag is enabled by default. The original ten vanilla flags remain the only flags exposed to the vanilla lobby-browser filter count; the new flag is still transmitted because the complete 32-bit `svFlags` value is sent through the existing `SVFL` packet.

## UI behaviour

The option appears in both places where Barony exposes game rules:

- Settings → Game Settings: `Equipment Wear`
- Character creation → Custom difficulty: `Disable Equipment Wear`

Only the host may change it. Clients display the synchronized value from the lobby/server flags.

## Presets

Practice, Normal, Nightmare and Tutorial keep equipment wear enabled, preserving Barony's original behaviour. To disable wear, the host must choose Custom and select `Disable Equipment Wear`.

## Persistence

`AllSettings` stores `equipment_wear_enabled`. The settings JSON version is increased from 25 to 26; configurations from earlier versions default to wear enabled.

## Scope

M2A only adds the option, persistence and multiplayer synchronization. It does not yet intercept any durability loss. M2B connects the flag to every relevant weapon, armor, shield, accessory and reusable-tool wear path.
