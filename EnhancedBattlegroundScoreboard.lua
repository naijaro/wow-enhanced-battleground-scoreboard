-- EnhancedBattlegroundScoreboard
-- Adds a class icon, class-colored name, class name, level, and a self marker
-- to each row of the end-of-battleground scoreboard,
-- e.g. "[icon] Narenthes (necromancer, 19)".
-- e.g. "[icon] Reverie (chronomancer, 19)".

-- The addon's folder name, provided by WoW as the first vararg to this file.
-- Deriving media paths from it keeps them working if the folder is ever renamed.
local ADDON_NAME = ...

-- Returns the addon folder name, or a literal fallback if the vararg is not a
-- string (only possible if this file is run outside normal addon loading).
local function getAddonName()
	if type(ADDON_NAME) == "string" then
		return ADDON_NAME
	end
	return "EnhancedBattlegroundScoreboard"
end

-- Level is hidden at max level. Set MAX_LEVEL_OVERRIDE to a number to force a
-- specific cap; leave nil to auto-detect (60 on Conquest of Azeroth, otherwise
-- the client's reported cap, e.g. 80 on stock WotLK).
local MAX_LEVEL_OVERRIDE = nil

-- Class icon atlas. Both layouts share the same texture file:
--   * Conquest of Azeroth: patch-A overrides it with a custom 8x4 sheet.
--   * Stock WotLK: the standard 4x4 sheet of the 10 original classes.
-- Cells are keyed by lowercase class display name; the active layout is chosen
-- by auto-detection (see coa_detect below).
local ICON_ATLAS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local ICON_SIZE = 14 -- pixel height/width of the inline icon

-- Self marker star texture shipped with the addon. Path derived from the folder
-- name so it survives a folder rename.
local STAR_TEXTURE = "Interface\\AddOns\\" .. getAddonName() .. "\\star.tga"
local STAR_ICON = "|T" .. STAR_TEXTURE .. ":0|t"

-- Conquest of Azeroth layout: 8 columns x 4 rows, {col, row} zero-based.
local COA_CELL = {
	-- row 0
	["barbarian"] = { 0, 0 }, ["chronomancer"] = { 1, 0 }, ["cultist"] = { 2, 0 },
	["death knight"] = { 3, 0 }, ["felsworn"] = { 4, 0 }, ["druid"] = { 5, 0 },
	["knight of xoroth"] = { 6, 0 }, ["guardian"] = { 7, 0 },
	-- row 1 (col 0 is an unused slot)
	["hunter"] = { 1, 1 }, ["mage"] = { 2, 1 }, ["templar"] = { 3, 1 },
	["necromancer"] = { 4, 1 }, ["paladin"] = { 5, 1 }, ["priest"] = { 6, 1 },
	["venomancer"] = { 7, 1 },
	-- row 2
	["pyromancer"] = { 0, 2 }, ["ranger"] = { 1, 2 }, ["reaper"] = { 2, 2 },
	["rogue"] = { 3, 2 }, ["shaman"] = { 4, 2 }, ["bloodmage"] = { 5, 2 },
	["runemaster"] = { 6, 2 }, ["starcaller"] = { 7, 2 },
	-- row 3
	["stormbringer"] = { 0, 3 }, ["sun cleric"] = { 1, 3 }, ["tinker"] = { 2, 3 },
	["warlock"] = { 3, 3 }, ["warrior"] = { 4, 3 }, ["primalist"] = { 5, 3 },
	["witch doctor"] = { 6, 3 }, ["witch hunter"] = { 7, 3 },
}

-- Standard WotLK layout: 4 columns x 4 rows, {col, row} zero-based.
local STD_CELL = {
	["warrior"] = { 0, 0 }, ["mage"] = { 1, 0 }, ["rogue"] = { 2, 0 }, ["druid"] = { 3, 0 },
	["hunter"] = { 0, 1 }, ["shaman"] = { 1, 1 }, ["priest"] = { 2, 1 }, ["warlock"] = { 3, 1 },
	["paladin"] = { 0, 2 }, ["death knight"] = { 1, 2 },
}

-- Class names that appear only in the CoA layout (every COA_CELL key that is not
-- also a standard class). Seeing one of these in the live scoreboard proves the
-- custom atlas is active; used to reinforce auto-detection at runtime.
local COA_EXCLUSIVE_CLASS_NAMES = {}
for key in pairs(COA_CELL) do
	if not STD_CELL[key] then
		COA_EXCLUSIVE_CLASS_NAMES[key] = true
	end
end

-- Normalize a class token/name for signature matching: upper-case, letters and
-- digits only (so "Death Knight" -> "DEATHKNIGHT").
local function coa_normalize(s)
	if type(s) ~= "string" then
		return ""
	end
	return (s:upper():gsub("[^A-Z0-9]", ""))
end

-- Signature classes that (as far as we know) only exist on Ascension /
-- Conquest of Azeroth. Their presence in the client's class list is a strong
-- signal that the custom 8x4 atlas is in use.
local COA_SIGNATURE = {
	NECROMANCER  = true,
	CHRONOMANCER = true,
	VENOMANCER   = true,
}

local coa_active -- cached auto-detect result: nil = not yet decided
local function coa_detect()
	-- Scan every source that might list class tokens or localized class names.
	local tables = {
		_G.LOCALIZED_CLASS_NAMES_MALE,
		_G.LOCALIZED_CLASS_NAMES_FEMALE,
		_G.CLASS_ICON_TCOORDS,
		_G.RAID_CLASS_COLORS,
	}
	for _, tbl in ipairs(tables) do
		if type(tbl) == "table" then
			for k, v in pairs(tbl) do
				if type(k) == "string" and COA_SIGNATURE[coa_normalize(k)] then
					return true
				end
				if type(v) == "string" and COA_SIGNATURE[coa_normalize(v)] then
					return true
				end
			end
		end
	end
	if type(_G.CLASS_SORT_ORDER) == "table" then
		for _, tok in ipairs(_G.CLASS_SORT_ORDER) do
			if type(tok) == "string" and COA_SIGNATURE[coa_normalize(tok)] then
				return true
			end
		end
	end
	return false
end

-- Returns the active cell table plus its column/row counts, detecting the
-- layout once on first use.
local function ClassLayout()
	if coa_active == nil then
		coa_active = coa_detect()
	end
	if coa_active then
		return COA_CELL, 8, 4
	end
	return STD_CELL, 4, 4
end

-- Max level: manual override if set, else 60 when Conquest of Azeroth is
-- detected (its custom cap), else the client's reported cap (80 on stock
-- WotLK). Cached after first use.
local maxLevel
local function MaxLevel()
	if maxLevel then
		return maxLevel
	end
	if type(MAX_LEVEL_OVERRIDE) == "number" then
		maxLevel = MAX_LEVEL_OVERRIDE
		return maxLevel
	end
	ClassLayout() -- ensure coa_active is populated
	if coa_active then
		maxLevel = 60
	elseif type(GetMaxPlayerLevel) == "function" then
		local m = GetMaxPlayerLevel()
		maxLevel = (type(m) == "number" and m > 0) and m or 80
	elseif type(MAX_PLAYER_LEVEL) == "number" and MAX_PLAYER_LEVEL > 0 then
		maxLevel = MAX_PLAYER_LEVEL
	else
		maxLevel = 80
	end
	return maxLevel
end

-- Runtime reinforcement of the initial auto-detection. coa_detect() is a best
-- guess from the client's class globals; if the scoreboard actually reports a
-- CoA-exclusive class, that is authoritative, so lock CoA in. One-directional:
-- we never switch back, since a stock client never reports these classes.
-- Returns true only when this call is what switched the layout to CoA.
local function ConfirmCoALayoutFromClass(className)
	if coa_active then
		return false
	end
	if className and COA_EXCLUSIVE_CLASS_NAMES[string.lower(className)] then
		coa_active = true
		maxLevel = nil -- recompute the cap now that we know it is CoA (60)
		return true
	end
	return false
end

local function ClassIcon(className)
	if not className then
		return nil
	end
	local cells, cols, rows = ClassLayout()
	local cell = cells[string.lower(className)]
	if not cell then
		return nil
	end
	local c, r = cell[1], cell[2]
	local cw, ch = 256 / cols, 256 / rows
	return string.format(
		"|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t",
		ICON_ATLAS, ICON_SIZE, ICON_SIZE,
		c * cw, (c + 1) * cw, r * ch, (r + 1) * ch
	)
end

-- Levels learned by targeting/mousing over enemies during this battleground.
-- Wiped whenever a new instance is entered (see the driver frame below).
local levelCache = {}

-- The scoreboard API does not report level, so we look it up from the
-- battleground raid roster (own faction) and fall back to any enemy level we
-- cached from targeting them. Unknown levels are omitted.
local function LevelForName(name)
	local num = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	for i = 1, num do
		local rname, _, _, rlevel = GetRaidRosterInfo(i)
		if rname == name then
			return rlevel
		end
	end
	local pnum = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	for i = 1, pnum do
		if UnitName("party" .. i) == name then
			return UnitLevel("party" .. i)
		end
	end
	if UnitName("player") == name then
		return UnitLevel("player")
	end
	return levelCache[name]
end

-- Record a unit's level if it's a player with a known level.
local function RecordUnitLevel(unit)
	if unit and UnitExists(unit) and UnitIsPlayer(unit) then
		local n, l = UnitName(unit), UnitLevel(unit)
		if n and type(l) == "number" and l > 0 then
			levelCache[n] = l
		end
	end
end

local function StripColor(s)
	if not s then return "" end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", "")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	return s
end

-- The class token from GetBattlefieldScore may be a custom Ascension class
-- (e.g. CULTIST) that isn't in RAID_CLASS_COLORS. Prefer the standard color,
-- otherwise reuse whatever color the name FontString already displays.
local function ColorChannel(v)
	v = tonumber(v)
	if not v then
		v = 1
	end
	if v < 0 then v = 0 elseif v > 1 then v = 1 end
	return math.floor(v * 255 + 0.5)
end

local function ColorHex(classToken, region)
	local c = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
	local r, g, b
	if c then
		r, g, b = c.r, c.g, c.b
	elseif region and region.GetTextColor then
		r, g, b = region:GetTextColor()
	end
	return string.format("ff%02x%02x%02x", ColorChannel(r), ColorChannel(g), ColorChannel(b))
end

-- Cache: for each scoreboard row button, remember which FontString holds the
-- player name so we don't have to rediscover it (and so it survives our own
-- edits, which change the visible text). Weak keys let any button that is ever
-- discarded be garbage collected instead of pinned by this table.
local nameRegions = setmetatable({}, { __mode = "k" })

-- The name text is not always a direct region of the row button (on Ascension
-- it lives in a nested child frame), so search descendants recursively.
local function FindNameRegion(frame, name, depth)
	depth = depth or 0
	if depth > 5 or not frame then
		return nil
	end
	if frame.GetRegions then
		for _, r in ipairs({ frame:GetRegions() }) do
			if r and r.GetObjectType and r:GetObjectType() == "FontString" then
				if StripColor(r:GetText()) == name then
					return r
				end
			end
		end
	end
	if frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			local found = FindNameRegion(child, name, depth + 1)
			if found then
				return found
			end
		end
	end
	return nil
end

local function GetNameRegion(button, name)
	local cached = nameRegions[button]
	if cached then
		return cached
	end
	local found = FindNameRegion(button, name, 0)
	if found then
		nameRegions[button] = found
	end
	return found
end

local function UpdateScoreNames()
	local numScores = GetNumBattlefieldScores() or 0
	if numScores == 0 then
		return
	end

	local offset = 0
	if WorldStateScoreScrollFrame then
		offset = FauxScrollFrame_GetOffset(WorldStateScoreScrollFrame) or 0
	end

	local layoutSwitchedToCoA = false
	local i = 1
	while true do
		local button = _G["WorldStateScoreButton" .. i]
		if not button then
			break
		end
		local index = offset + i
		if index <= numScores then
			local name, _, _, _, _, _, _, _, class, classToken = GetBattlefieldScore(index)
			if name then
				if ConfirmCoALayoutFromClass(class) then
					layoutSwitchedToCoA = true
				end
				local region = GetNameRegion(button, name)
				if region then
					local inner = string.lower(class or "?")
					local lvl = LevelForName(name)
					if lvl and lvl > 0 and lvl ~= MaxLevel() then
						inner = string.format("%s, %d", inner, lvl)
					end
					local tag = "(" .. inner .. ")"
					if name == UnitName("player") then
						tag = tag .. " " .. STAR_ICON
					end
					local icon = ClassIcon(class)
					region:SetText(string.format(
						"%s|c%s%s|r |cffb0b0b0%s|r",
						icon and (icon .. " ") or "",
						ColorHex(classToken, region), name, tag
					))
				end
			end
		end
		i = i + 1
	end

	-- If a CoA-exclusive class proved the layout mid-pass, re-render once (still
	-- synchronous, before the frame paints) so every row -- including standard
	-- classes already drawn with the wrong atlas -- uses the correct cells.
	-- Safe from recursion: coa_active is now true, so no further switch occurs.
	if layoutSwitchedToCoA then
		return UpdateScoreNames()
	end
end

-- Keep the icon textures resident in memory. Inline |T...|t escapes render as
-- raw text (e.g. "|TInterface\GLUES\...|") until their texture has finished
-- loading; the class atlas streams from patch-A.MPQ, so on a cold client it can
-- briefly show as text before appearing. A persistent 1px, fully transparent
-- texture that references each path forces the client to load and hold it.
local preloaded = {}
local function Preload(path)
	local t = UIParent:CreateTexture(nil, "BACKGROUND")
	t:SetTexture(path)
	t:SetWidth(1)
	t:SetHeight(1)
	t:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	t:SetAlpha(0)
	preloaded[#preloaded + 1] = t -- keep a reference so it is never collected
end
Preload(ICON_ATLAS)
Preload(STAR_TEXTURE)

-- Primary path: runs right after Blizzard repopulates the scoreboard.
if type(WorldStateScoreFrame_Update) == "function" then
	hooksecurefunc("WorldStateScoreFrame_Update", UpdateScoreNames)
end

-- Fallback path: refresh a frame after the score-data event, in case the
-- update function is named differently on this client.
local driver = CreateFrame("Frame")
local pending = false
driver:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(self, event)
	if event == "UPDATE_BATTLEFIELD_SCORE" then
		pending = true
	elseif event == "PLAYER_TARGET_CHANGED" then
		RecordUnitLevel("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		RecordUnitLevel("mouseover")
	elseif event == "PLAYER_ENTERING_WORLD" then
		wipe(levelCache)
		wipe(nameRegions)
	end
end)
driver:SetScript("OnUpdate", function()
	if pending then
		pending = false
		UpdateScoreNames()
	end
end)

-- Diagnostics: type /ebs debug while the scoreboard is open, paste me the output.
SLASH_EBS1 = "/ebs"
SlashCmdList["EBS"] = function(msg)
	msg = string.lower(msg or "")
	msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
	local cf = DEFAULT_CHAT_FRAME or ChatFrame1
	local function p(...)
		if cf then
			cf:AddMessage(table.concat({ ... }, " "))
		end
	end
	if msg ~= "debug" then
		p("|cff33ff99EnhancedBattlegroundScoreboard|r: type /ebs debug for diagnostics.")
		return
	end
	p("|cff33ff99EnhancedBattlegroundScoreboard|r diagnostics:")
	ClassLayout() -- ensure detection has run
	p("  Class atlas:", coa_active and "Conquest of Azeroth (8x4)" or "standard WotLK (4x4)")
	p("  Max level (level hidden at):", tostring(MaxLevel()))
	p("  WorldStateScoreFrame:", WorldStateScoreFrame and "exists" or "MISSING")
	p("  WorldStateScoreFrame_Update:", type(WorldStateScoreFrame_Update))
	p("  GetNumBattlefieldScores:", tostring(GetNumBattlefieldScores and GetNumBattlefieldScores()))
	p("  MAX_WORLDSTATE_SCORE_BUTTONS:", tostring(MAX_WORLDSTATE_SCORE_BUTTONS))
	if (GetNumBattlefieldScores and GetNumBattlefieldScores() or 0) > 0 then
		local a = { GetBattlefieldScore(1) }
		p("  GetBattlefieldScore(1) ->", #a, "values:")
		for idx = 1, #a do
			p("    [" .. idx .. "] =", tostring(a[idx]))
		end
	end
	local b1 = _G["WorldStateScoreButton1"]
	p("  WorldStateScoreButton1:", b1 and "exists" or "MISSING")
	local function dump(frame, depth)
		if not frame or depth > 5 then return end
		local pad = string.rep("  ", depth)
		if frame.GetRegions then
			for _, r in ipairs({ frame:GetRegions() }) do
				if r.GetObjectType and r:GetObjectType() == "FontString" then
					local t = r:GetText()
					if t and t ~= "" then
						p(pad .. "FS", "name=" .. tostring(r.GetName and r:GetName()), "text=" .. tostring(t))
					end
				end
			end
		end
		if frame.GetChildren then
			for _, child in ipairs({ frame:GetChildren() }) do
				dump(child, depth + 1)
			end
		end
	end
	if b1 then
		p("  Deep FontString dump for Button1:")
		dump(b1, 2)
	end
end
