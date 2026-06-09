-- AppearanceConfig.luau
-- Character appearance presets: gender (template) and skin tones.
-- Loaded by CharacterAppearanceService (server) and CharacterCreatorController (client).
--
-- Skin tones are applied to the standard R15 BodyColors instance.
-- Add new tones by adding entries with a stable ID and Color3 value.

local AppearanceConfig = {}

AppearanceConfig.Genders = {
	male = {
		id = "male",
		name = "Male",
		templateName = "Male",  -- ServerStorage.AvatarTemplates.<templateName>
	},
	female = {
		id = "female",
		name = "Female",
		templateName = "Female",
	},
}

AppearanceConfig.GenderOrder = { "male", "female" }

AppearanceConfig.SkinTones = {
	tone_1 = { id = "tone_1", name = "Porcelain", color = Color3.fromRGB(242, 218, 195) },
	tone_2 = { id = "tone_2", name = "Fair",      color = Color3.fromRGB(215, 175, 145) },
	tone_3 = { id = "tone_3", name = "Olive",     color = Color3.fromRGB(180, 130,  95) },
	tone_4 = { id = "tone_4", name = "Bronze",    color = Color3.fromRGB(130,  85,  55) },
	tone_5 = { id = "tone_5", name = "Deep",      color = Color3.fromRGB( 75,  50,  35) },
}

AppearanceConfig.SkinToneOrder = { "tone_1", "tone_2", "tone_3", "tone_4", "tone_5" }

AppearanceConfig.Defaults = {
	gender = "male",
	skin_tone = "tone_2",
}

function AppearanceConfig.isValidGender(id)
	return AppearanceConfig.Genders[id] ~= nil
end

function AppearanceConfig.isValidSkinTone(id)
	return AppearanceConfig.SkinTones[id] ~= nil
end

return AppearanceConfig
