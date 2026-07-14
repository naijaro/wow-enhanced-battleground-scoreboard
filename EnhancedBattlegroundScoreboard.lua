-- EnhancedBattlegroundScoreboard
-- Adds a class icon, class-colored name, class name, level, and a self marker
-- to each row of the end-of-battleground scoreboard,
-- e.g. "[icon] Narenthes (necromancer, 19)".
-- e.g. "[icon] Reverie (choronomancer, 19)".

-- Level is hidden at max level.
local MAX_LEVEL = 60

-- Class icon atlas (patch-A override of the character-create classes sheet).
-- 8 columns x 4 rows; cells are keyed by lowercase class display name.
local ICON_ATLAS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local ICON_SIZE = 14 -- pixel height/width of the inline icon
local ATLAS_COLS, ATLAS_ROWS = 8, 4

local CLASS_CELL = {
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

local CELL_W = 256 / ATLAS_COLS -- declared texel width per cell (256px atlas space)
local CELL_H = 256 / ATLAS_ROWS

local function ClassIcon(className)
	local cell = className and CLASS_CELL[string.lower(className)]
	if not cell then
		return nil
	end
	local c, r = cell[1], cell[2]
	return string.format(
		"|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t",
		ICON_ATLAS, ICON_SIZE, ICON_SIZE,
		c * CELL_W, (c + 1) * CELL_W, r * CELL_H, (r + 1) * CELL_H
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
				local region = GetNameRegion(button, name)
				if region then
					local inner = string.lower(class or "?")
					local lvl = LevelForName(name)
					if lvl and lvl > 0 and lvl ~= MAX_LEVEL then
						inner = string.format("%s, %d", inner, lvl)
					end
					local tag = "(" .. inner .. ")"
					if name == UnitName("player") then
						tag = tag .. " |TInterface\\AddOns\\EnhancedBattlegroundScoreboard\\star.tga:0|t"
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
end

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
