-- Default priority lists for every TBC class and talent tree.
-- Each entry: spell = exact spell name, cond = condition (see Conditions.lua),
-- off = true for abilities that are not on the global cooldown.
-- Healing trees are empty on purpose: they use Freestyle (every cast is
-- judged against the beat) because healing is reactive, not a rotation.
-- Players can edit all of these in-game with /beat editor.
local _, BC = ...

local SHOUT = 'buff("Battle Shout") < 3 and buff("Commanding Shout") == 0'
local CURSE = 'debuff("Curse of Agony") == 0 and debuff("Curse of Doom") == 0 and debuffAny("Curse of the Elements") == 0 and debuffAny("Curse of Recklessness") == 0'
local LIFETAP = "manaPct < 15 and hp > 50"
local SND = 'buff("Slice and Dice") < 2 and combo >= 1'

BC.SpecNames = {
	WARRIOR = { "Arms", "Fury", "Protection" },
	PALADIN = { "Holy", "Protection", "Retribution" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
	ROGUE = { "Assassination", "Combat", "Subtlety" },
	PRIEST = { "Discipline", "Holy", "Shadow" },
	SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	MAGE = { "Arcane", "Fire", "Frost" },
	WARLOCK = { "Affliction", "Demonology", "Destruction" },
	DRUID = { "Balance", "Feral Combat", "Restoration" },
}

BC.ClassNames = {
	WARRIOR = "Warrior",
	PALADIN = "Paladin",
	HUNTER = "Hunter",
	ROGUE = "Rogue",
	PRIEST = "Priest",
	SHAMAN = "Shaman",
	MAGE = "Mage",
	WARLOCK = "Warlock",
	DRUID = "Druid",
}

local function e(spell, cond, off)
	return { spell = spell, cond = cond or "", off = off or nil }
end

BC.RotationDefaults = {
	WARRIOR = {
		{ -- Arms
			e("Battle Shout", SHOUT),
			e("Execute", "targetHp < 20"),
			e("Mortal Strike"),
			e("Whirlwind"),
			e("Overpower"),
			e("Slam", "rage >= 30"),
			e("Heroic Strike", "rage >= 55", true),
		},
		{ -- Fury
			e("Battle Shout", SHOUT),
			e("Execute", "targetHp < 20"),
			e("Bloodthirst"),
			e("Whirlwind"),
			e("Rampage", 'buff("Rampage") < 3'),
			e("Heroic Strike", "rage >= 50", true),
		},
		{ -- Protection
			e("Shield Block", 'buff("Shield Block") == 0', true),
			e("Shield Slam"),
			e("Revenge"),
			e("Thunder Clap", 'debuffAny("Thunder Clap") < 2'),
			e("Demoralizing Shout", 'debuffAny("Demoralizing Shout") < 2 and debuffAny("Demoralizing Roar") == 0'),
			e("Devastate"),
			e("Sunder Armor", 'not known("Devastate")'),
			e("Heroic Strike", "rage >= 40", true),
		},
	},
	PALADIN = {
		{}, -- Holy: Freestyle
		{ -- Protection
			e("Righteous Fury", 'buff("Righteous Fury") == 0'),
			e("Seal of Righteousness", 'buff("Seal of Righteousness") == 0 and buff("Seal of Vengeance") == 0'),
			e("Holy Shield", 'buff("Holy Shield") < 1'),
			e("Avenger's Shield"),
			e("Judgement"),
			e("Consecration"),
		},
		{ -- Retribution
			e("Seal of Command", 'buff("Seal of Command") == 0 and buff("Seal of Blood") == 0'),
			e("Judgement"),
			e("Crusader Strike"),
			e("Hammer of Wrath", "targetHp < 20"),
			e("Exorcism", 'targetIs("Undead") or targetIs("Demon")'),
			e("Consecration", "manaPct > 50"),
		},
	},
	HUNTER = {
		{ -- Beast Mastery
			e("Hunter's Mark", 'debuffAny("Hunter\'s Mark") == 0'),
			e("Kill Command", "", true),
			e("Bestial Wrath", "boss"),
			e("Rapid Fire", "boss", true),
			e("Multi-Shot"),
			e("Arcane Shot", "manaPct > 40"),
			e("Steady Shot"),
		},
		{ -- Marksmanship
			e("Hunter's Mark", 'debuffAny("Hunter\'s Mark") == 0'),
			e("Kill Command", "", true),
			e("Rapid Fire", "boss", true),
			e("Multi-Shot"),
			e("Arcane Shot", "manaPct > 40"),
			e("Steady Shot"),
		},
		{ -- Survival
			e("Hunter's Mark", 'debuffAny("Hunter\'s Mark") == 0'),
			e("Kill Command", "", true),
			e("Rapid Fire", "boss", true),
			e("Multi-Shot"),
			e("Steady Shot"),
			e("Arcane Shot", "manaPct > 40"),
		},
	},
	ROGUE = {
		{ -- Assassination
			e("Slice and Dice", SND),
			e("Rupture", 'combo >= 4 and debuff("Rupture") < 1'),
			e("Envenom", 'combo >= 4 and buff("Slice and Dice") > 5'),
			e("Eviscerate", "combo >= 5"),
			e("Mutilate"),
			e("Sinister Strike", 'not known("Mutilate")'),
		},
		{ -- Combat
			e("Slice and Dice", SND),
			e("Blade Flurry", "boss"),
			e("Adrenaline Rush", "boss"),
			e("Rupture", 'combo >= 5 and debuff("Rupture") < 1 and buff("Slice and Dice") > 6'),
			e("Eviscerate", "combo >= 5"),
			e("Sinister Strike"),
		},
		{ -- Subtlety
			e("Slice and Dice", SND),
			e("Rupture", 'combo >= 5 and debuff("Rupture") < 1'),
			e("Eviscerate", "combo >= 5"),
			e("Hemorrhage"),
			e("Sinister Strike", 'not known("Hemorrhage")'),
		},
	},
	PRIEST = {
		{}, -- Discipline: Freestyle
		{}, -- Holy: Freestyle
		{ -- Shadow
			e("Shadowform", 'buff("Shadowform") == 0'),
			e("Vampiric Touch", 'debuff("Vampiric Touch") < 1.5'),
			e("Shadow Word: Pain", 'debuff("Shadow Word: Pain") < 1'),
			e("Vampiric Embrace", 'debuff("Vampiric Embrace") == 0'),
			e("Mind Blast"),
			e("Shadow Word: Death", "hp > 40"),
			e("Shadowfiend", "manaPct < 60 and boss"),
			e("Mind Flay"),
		},
	},
	SHAMAN = {
		{ -- Elemental
			e("Water Shield", 'buff("Water Shield") == 0 and buff("Lightning Shield") == 0'),
			e("Elemental Mastery", "boss", true),
			e("Flame Shock", 'debuff("Flame Shock") < 1'),
			e("Chain Lightning"),
			e("Lightning Bolt"),
		},
		{ -- Enhancement
			e("Water Shield", 'buff("Water Shield") == 0 and buff("Lightning Shield") == 0'),
			e("Stormstrike"),
			e("Flame Shock", 'debuff("Flame Shock") == 0 and debuffAny("Stormstrike") == 0'),
			e("Earth Shock"),
		},
		{}, -- Restoration: Freestyle
	},
	MAGE = {
		{ -- Arcane
			e("Arcane Power", "boss", true),
			e("Presence of Mind", "boss", true),
			e("Arcane Blast", "manaPct > 35"),
			e("Frostbolt"),
		},
		{ -- Fire
			e("Combustion", "boss", true),
			e("Scorch", 'debuffAnyStacks("Fire Vulnerability") < 5 or debuffAny("Fire Vulnerability") < 4'),
			e("Fire Blast", "moving"),
			e("Fireball"),
		},
		{ -- Frost
			e("Icy Veins", "boss", true),
			e("Summon Water Elemental", "boss and not pet"),
			e("Frostbolt"),
		},
	},
	WARLOCK = {
		{ -- Affliction
			e("Life Tap", LIFETAP),
			e("Curse of Agony", CURSE),
			e("Corruption", 'debuff("Corruption") < 1'),
			e("Unstable Affliction", 'debuff("Unstable Affliction") < 1.5'),
			e("Siphon Life", 'debuff("Siphon Life") < 1'),
			e("Shadow Bolt"),
		},
		{ -- Demonology
			e("Life Tap", LIFETAP),
			e("Curse of Agony", CURSE),
			e("Corruption", 'debuff("Corruption") < 1'),
			e("Immolate", 'debuff("Immolate") < 2'),
			e("Shadow Bolt"),
		},
		{ -- Destruction
			e("Life Tap", LIFETAP),
			e("Curse of Agony", CURSE),
			e("Immolate", 'debuff("Immolate") < 2'),
			e("Shadow Bolt"),
		},
	},
	DRUID = {
		{ -- Balance
			e("Moonkin Form", 'buff("Moonkin Form") == 0'),
			e("Faerie Fire", 'debuffAny("Faerie Fire") == 0'),
			e("Insect Swarm", 'debuff("Insect Swarm") < 1'),
			e("Moonfire", 'debuff("Moonfire") < 1'),
			e("Starfire"),
			e("Wrath", 'not known("Starfire")'),
		},
		{ -- Feral Combat (handles both Cat and Bear form)
			e("Mangle (Bear)", "bear"),
			e("Lacerate", 'bear and (debuffStacks("Lacerate") < 5 or debuff("Lacerate") < 3)'),
			e("Demoralizing Roar", 'bear and debuffAny("Demoralizing Roar") == 0 and debuffAny("Demoralizing Shout") == 0'),
			e("Maul", "bear and rage >= 40", true),
			e("Mangle (Cat)", 'cat and debuffAny("Mangle (Cat)") < 1 and debuffAny("Mangle (Bear)") == 0'),
			e("Rip", 'cat and combo >= 5 and debuff("Rip") < 1'),
			e("Ferocious Bite", 'cat and combo >= 5 and debuff("Rip") > 4'),
			e("Shred", "cat"),
		},
		{}, -- Restoration: Freestyle
	},
}
