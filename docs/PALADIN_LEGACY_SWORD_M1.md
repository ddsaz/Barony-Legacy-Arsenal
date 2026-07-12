# Paladin Legacy Sword — Milestone 1

## Purpose

Milestone 1 makes the marked Paladin weapon visibly distinct while preserving every combat value and placeholder asset validated in Milestone 0.

## Visible identity

The provisional English name is:

```text
Oathblade
```

It is deliberately stored in `src/legacy_arsenal.hpp` rather than in Barony's language files. Once the weapon becomes its own `ItemType`, the final name and translations will move into the normal localisation data.

## Source integration

`scripts/windows/apply-paladin-m1.ps1` updates `src/items.cpp` in three controlled places:

1. Includes `legacy_arsenal.hpp`.
2. Uses `Oathblade` when `Item::description()` appends the identified item name to the tooltip title.
3. Returns `Oathblade` from `Item::getName()` for menus and messages.

The normal status prefix and beatitude remain intact, so the first tooltip should read similarly to:

```text
Servicable Oathblade (+0)
```

The spelling of the existing Barony status prefix is not changed by this milestone.

## Unchanged behaviour

- Item type: `CLAYMORE_SWORD`
- Starting status: `SERVICABLE`
- Starting beatitude: `0`
- Base weapon attack: the normal claymore value
- World model: normal claymore placeholder
- First-person model: normal claymore placeholder
- Save/network identity: `Item::appearance == 0x4C415331`

## Acceptance test

A new Paladin should see `Oathblade` in the inventory tooltip and wherever Barony uses `Item::getName()`. Attacking, saving and loading must continue to behave exactly as in Milestone 0.

Durability interception is Milestone 2. It will modify the actual degradation paths rather than restoring the weapon status every frame.
