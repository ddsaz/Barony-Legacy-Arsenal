# Paladin Legacy Sword — Milestone 0

## Purpose

Milestone 0 proves that the first legendary class weapon can exist as a stable item identity before adding progression, custom attacks, spells or assets.

## Scope

The first playable prototype will:

1. Replace the Paladin's ordinary starting claymore with a marked legendary claymore.
2. Keep exactly the same item type, status, beatitude and therefore initial combat effectiveness as the ordinary starting claymore.
3. Use the existing claymore world, inventory and first-person assets as placeholders.
4. Preserve a distinct identity using `Item::appearance`.
5. Keep that identity through the existing item copy, save/load and network serialization paths.
6. Add a central `LegacyArsenal::isPaladinLegacySword()` predicate so later mechanics never depend on scattered numeric checks.

## Identity marker

```cpp
LegacyArsenal::PALADIN_LEGACY_SWORD_APPEARANCE
```

The marker is the unsigned 32-bit value `0x4C415331`, corresponding to `LAS1`.

Barony already stores `appearance` in every `Item`. Existing rendering uses the value modulo the number of item variations, so the prototype still resolves to a valid claymore model.

## Deliberately deferred

This milestone does not yet add:

- a custom displayed name;
- a new `ItemType` entry;
- new models, sprites or sounds;
- global indestructible-equipment settings;
- legacy levels;
- Thaumaturgy;
- guard, auras, Filo Radiante, Corte del Juramento or the ultimate;
- final multiplayer validation.

Indestructibility is the next source-level change after the item identity and starting loadout compile and run correctly.

## Acceptance test

A local Paladin should:

- start with one equipped claymore;
- deal the same initial damage as the unmodified Paladin;
- show the normal claymore placeholder model;
- survive save and reload without turning into a different item;
- be recognized by the debug predicate during later implementation.
