# Legacy Arsenal development map

## Stable base

The first Windows/Steamworks baseline is frozen on:

```text
bootstrap-steamworks-v1
```

Its validated state and proprietary dependency rules are documented in `docs/STEAMWORKS_BASELINE.md`.

## Branch responsibilities

- `master`: upstream-oriented fork history.
- `build/windows-bootstrap`: compiler, dependency and SDK compatibility work.
- `bootstrap-steamworks-v1`: frozen known-good Steamworks baseline.
- `feature/paladin-legacy-sword`: gameplay implementation for the first legendary class weapon.

## Immediate gameplay milestone

The first playable milestone must remain deliberately small:

1. Add a separate legendary sword item.
2. Give it to the Paladin at character creation when the feature is enabled.
3. Match the starting claymore's initial combat effectiveness.
4. Prevent durability loss.
5. Preserve the item through save/load.
6. Synchronize the item in multiplayer.
7. Use provisional existing assets until the mechanics are stable.

Auras, alternate attacks, Thaumaturgy and the ultimate ability come after this object-level milestone is stable.
