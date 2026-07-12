#pragma once

#include "items.hpp"

namespace LegacyArsenal
{
	// Milestone 0 stores the Paladin legendary sword as a distinguished
	// CLAYMORE_SWORD. Item::appearance is already saved and synchronized by
	// Barony, while the renderer reduces it modulo the claymore variations, so
	// this marker keeps the normal claymore placeholder model.
	constexpr Uint32 PALADIN_LEGACY_SWORD_APPEARANCE = 0x4C415331u; // "LAS1"

	inline bool isPaladinLegacySword(const Item* item)
	{
		return item
			&& item->type == CLAYMORE_SWORD
			&& item->appearance == PALADIN_LEGACY_SWORD_APPEARANCE;
	}
}
