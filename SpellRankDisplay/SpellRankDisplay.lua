-- Spell Rank Display
-- Adds a small rank number ("1", "2", ...) to the default Blizzard action
-- buttons. It never touches secure attributes or replaces Blizzard functions;
-- it only post-hooks updates and draws a label.

local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

ns.defaults = {
    position    = "TOPLEFT",
    font        = "Fonts\\ARIALN.TTF",
    fontSize    = 14,
    outline     = "OUTLINE",
    shadow      = true,
    padding     = 2,
    lowerColor  = { r = 1, g = 0.25, b = 0.25 },
    highestColor = { r = 1, g = 1, b = 1 },
    showHighest = true,
}

-- anchor point -> x direction, y direction (multiplied by padding),
-- horizontal justification
ns.POSITIONS = {
    TOPLEFT     = {  1, -1, "LEFT" },
    TOP         = {  0, -1, "CENTER" },
    TOPRIGHT    = { -1, -1, "RIGHT" },
    LEFT        = {  1,  0, "LEFT" },
    RIGHT       = { -1,  0, "RIGHT" },
    CENTER      = {  0,  0, "CENTER" },
    BOTTOMLEFT  = {  1,  1, "LEFT" },
    BOTTOM      = {  0,  1, "CENTER" },
    BOTTOMRIGHT = { -1,  1, "RIGHT" },
}

-- Font files shipped with the game client. There is no API to enumerate
-- them; if a file is missing, StyleLabel falls back to the default font.
ns.FONTS = {
    { name = "Arial Narrow",   path = "Fonts\\ARIALN.TTF" },
    { name = "Friz Quadrata",  path = "Fonts\\FRIZQT__.TTF" },
    { name = "Morpheus",       path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri",         path = "Fonts\\SKURRI.TTF" },
    { name = "2002",           path = "Fonts\\2002.TTF" },
    { name = "2002 Bold",      path = "Fonts\\2002B.TTF" },
    { name = "MoK",            path = "Fonts\\K_Pagetext.TTF" },
    { name = "Nimrod MT",      path = "Fonts\\NIM_____.ttf" },
    { name = "YDIWingsM",      path = "Fonts\\K_Damage.TTF" },
}

ns.FONT_SIZE_MIN, ns.FONT_SIZE_MAX = 8, 24

ns.OUTLINES = {
    { name = "None",          value = "NONE" },
    { name = "Outline",       value = "OUTLINE" },
    { name = "Thick outline", value = "THICKOUTLINE" },
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns.ResetSettings()
    wipe(ns.db)
    CopyDefaults(ns.defaults, ns.db)
end

---------------------------------------------------------------------------
-- Label styling (shared with the options preview)
---------------------------------------------------------------------------

function ns.StyleLabel(label, button)
    local db = ns.db
    local pos = ns.POSITIONS[db.position] and db.position or "TOPLEFT"
    local p = ns.POSITIONS[pos]

    local flags = (db.outline == "NONE") and "" or db.outline
    if not label:SetFont(db.font, db.fontSize, flags) then
        label:SetFont(ns.defaults.font, db.fontSize, flags)
    end

    if db.shadow then
        label:SetShadowColor(0, 0, 0, 1)
        label:SetShadowOffset(1, -1)
    else
        label:SetShadowColor(0, 0, 0, 0)
        label:SetShadowOffset(0, 0)
    end

    label:ClearAllPoints()
    label:SetPoint(pos, button, pos, p[1] * db.padding, p[2] * db.padding)
    label:SetJustifyH(p[3])
end

-- Sets text and color, or hides the label if the settings say so.
function ns.PaintLabel(label, rank, isLower)
    local db = ns.db
    if not isLower and not db.showHighest then
        label:Hide()
        return
    end
    local c = isLower and db.lowerColor or db.highestColor
    label:SetText(rank)
    label:SetTextColor(c.r, c.g, c.b)
    label:Show()
end

---------------------------------------------------------------------------
-- Spell / rank lookup
---------------------------------------------------------------------------

local labels = setmetatable({}, { __mode = "k" })   -- button -> FontString
local hookedButtons = setmetatable({}, { __mode = "k" })
local requestedSpells = {}

local BUTTON_PREFIXES = {
    "ActionButton",
    "BonusActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button",
}
local BUTTONS_PER_BAR = 12

local RefreshAll -- forward declaration

local GetSubtext = GetSpellSubtext or (C_Spell and C_Spell.GetSpellSubtext)

local function RequestSpellData(spellID)
    if requestedSpells[spellID] then return end
    requestedSpells[spellID] = true
    if Spell and Spell.CreateFromSpellID then
        local spell = Spell:CreateFromSpellID(spellID)
        -- Data already loaded: a blank subtext means the spell has no ranks.
        if spell and spell.IsSpellDataCached and spell:IsSpellDataCached() then
            return
        end
        if spell and spell.ContinueOnSpellLoad then
            spell:ContinueOnSpellLoad(function()
                -- A spellbook scan may have skipped this spell while it
                -- was uncached, so rescan before the next redraw.
                spellbookDirty = true
                RefreshAll()
            end)
        end
    end
end

local function GetRankForSpell(spellID)
    if not spellID then return nil end

    local text = GetSubtext and GetSubtext(spellID)
    if (not text or text == "") and GetSpellInfo then
        -- Older clients returned the rank as GetSpellInfo's second value.
        local _, rank = GetSpellInfo(spellID)
        if type(rank) == "string" then text = rank end
    end

    if not text or text == "" then
        RequestSpellData(spellID)
        return nil
    end

    -- "Rank 2" -> "2". Non-ranked subtexts ("Racial", "Passive") have no digits.
    return text:match("(%d+)")
end

local function GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
end

---------------------------------------------------------------------------
-- Highest known rank per spell name, built from the player's spellbook
---------------------------------------------------------------------------

local highestRank = {}      -- spell name -> highest known rank (number)
local spellbookDirty = true

local function GetSpellTab(tab)
    if GetSpellTabInfo then
        local _, _, offset, numSlots = GetSpellTabInfo(tab)
        return offset, numSlots
    elseif C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo then
        local info = C_SpellBook.GetSpellBookSkillLineInfo(tab)
        if info then return info.itemIndexOffset, info.numSpellBookItems end
    end
end

local function GetSpellbookSpellID(index)
    if GetSpellBookItemInfo then
        local itemType, spellID = GetSpellBookItemInfo(index, BOOKTYPE_SPELL or "spell")
        if itemType == "SPELL" then return spellID end
    elseif C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local info = C_SpellBook.GetSpellBookItemInfo(index, bank)
        if info and Enum and Enum.SpellBookItemType
            and info.itemType == Enum.SpellBookItemType.Spell then
            return info.spellID
        end
    end
end

local function ScanSpellbook()
    spellbookDirty = false
    wipe(highestRank)

    local numTabs = (GetNumSpellTabs and GetNumSpellTabs())
        or (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
            and C_SpellBook.GetNumSpellBookSkillLines())
        or 0

    for tab = 1, numTabs do
        local offset, numSlots = GetSpellTab(tab)
        if offset and numSlots then
            for index = offset + 1, offset + numSlots do
                local spellID = GetSpellbookSpellID(index)
                local rank = tonumber(GetRankForSpell(spellID))
                local name = rank and GetSpellName(spellID)
                if name and rank > (highestRank[name] or 0) then
                    highestRank[name] = rank
                end
            end
        end
    end
end

local function IsLowerRank(spellID, rank)
    local name = GetSpellName(spellID)
    local best = name and highestRank[name]
    return best ~= nil and tonumber(rank) < best
end

local function GetSpellIDForAction(action)
    local actionType, id, subType = GetActionInfo(action)
    if actionType == "spell" then
        return id
    elseif actionType == "macro" then
        if subType == "spell" then
            return id
        elseif GetMacroSpell then
            return GetMacroSpell(id)
        end
    end
    return nil
end

local function GetButtonAction(button)
    local action = button.action
    if not action and ActionButton_GetPagedID then
        action = ActionButton_GetPagedID(button)
    end
    return action
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function GetLabel(button)
    local label = labels[button]
    if label then return label end

    -- Draw on a child frame raised above the cooldown swipe so the number
    -- stays readable while the spell is on cooldown.
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)

    label = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ns.StyleLabel(label, button)

    labels[button] = label
    return label
end

local function UpdateButton(button)
    if type(button) ~= "table" or not ns.db then return end

    local rank, spellID
    local action = GetButtonAction(button)
    if action and HasAction(action) then
        spellID = GetSpellIDForAction(action)
        rank = GetRankForSpell(spellID)
    end

    if rank then
        if spellbookDirty then ScanSpellbook() end
        ns.PaintLabel(GetLabel(button), rank, IsLowerRank(spellID, rank))
    elseif labels[button] then
        labels[button]:Hide()
    end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

local function HookButton(button)
    if hookedButtons[button] then return end
    hookedButtons[button] = true
    -- Modern (mixin-based) action buttons. UpdateAction usually calls Update
    -- itself, so this can run twice per change; that's cheap, and hooking
    -- both covers clients where only one of them fires.
    if type(button.Update) == "function" then
        hooksecurefunc(button, "Update", UpdateButton)
    end
    if type(button.UpdateAction) == "function" then
        hooksecurefunc(button, "UpdateAction", UpdateButton)
    end
end

local function ForEachButton(fn)
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, BUTTONS_PER_BAR do
            local button = _G[prefix .. i]
            if button then fn(button) end
        end
    end
end

-- Older (function-based) action button code.
if ActionButton_Update then
    hooksecurefunc("ActionButton_Update", UpdateButton)
end
if ActionButton_UpdateAction then
    hooksecurefunc("ActionButton_UpdateAction", UpdateButton)
end

---------------------------------------------------------------------------
-- Refreshing
---------------------------------------------------------------------------

local refreshPending = false

local function DoRefresh()
    refreshPending = false
    ForEachButton(UpdateButton)
end

-- Defer one frame so Blizzard's own handlers (paging, slot changes) run first.
function RefreshAll()
    if refreshPending then return end
    refreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, DoRefresh)
    else
        DoRefresh()
    end
end

-- Called by the options panel whenever a setting changes.
function ns.ApplySettings()
    for button, label in pairs(labels) do
        ns.StyleLabel(label, button)
    end
    DoRefresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local EVENTS = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM",
    "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB",
    "UPDATE_MACROS",
}
for _, event in ipairs(EVENTS) do
    pcall(frame.RegisterEvent, frame, event) -- tolerate events a client lacks
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            SpellRankDisplayDB = CopyDefaults(ns.defaults, SpellRankDisplayDB or {})
            ns.db = SpellRankDisplayDB
            -- Keep sizes saved under older, wider limits within range.
            ns.db.fontSize = math.min(math.max(ns.db.fontSize,
                ns.FONT_SIZE_MIN), ns.FONT_SIZE_MAX)
            if ns.CreateOptions then ns.CreateOptions() end
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        ForEachButton(HookButton)
    end
    if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_TAB" then
        spellbookDirty = true
    end
    RefreshAll()
end)
