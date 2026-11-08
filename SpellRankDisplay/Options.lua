-- Options panel for Spell Rank Display (Esc > Options > AddOns).
-- Built from plain frames rather than Blizzard dropdown/slider templates,
-- which vary between client versions and can spread taint.

local _, ns = ...

local PANEL_NAME = "Spell Rank Display"
-- Preview icons: Smite (bright) and Lesser Heal (dark).
local PREVIEW_ICON_BRIGHT = "Interface\\Icons\\Spell_Holy_HolySmite"
local PREVIEW_ICON_DARK = "Interface\\Icons\\Spell_Holy_LesserHeal"
local GOLD = { 1, 0.82, 0 }

local panel
local widgets = {}          -- every widget with a :Refresh() method

local function RefreshWidgets()
    for _, w in ipairs(widgets) do w:Refresh() end
end

local function OnSettingChanged()
    ns.ApplySettings()
    RefreshWidgets()
end

---------------------------------------------------------------------------
-- Color picker (supports both the new and the old ColorPickerFrame API)
---------------------------------------------------------------------------

-- Looks the color up by key on every change rather than holding the table,
-- so a Reset while the picker is open doesn't leave it editing a stale copy.
local function OpenColorPicker(key, onChange)
    local color = ns.db[key]
    local prev = { r = color.r, g = color.g, b = color.b }

    local function apply(r, g, b)
        local c = ns.db[key]
        c.r, c.g, c.b = r, g, b
        onChange()
    end
    local function swatchFunc()
        apply(ColorPickerFrame:GetColorRGB())
    end
    local function cancelFunc()
        apply(prev.r, prev.g, prev.b)
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r, g = color.g, b = color.b,
            hasOpacity = false,
            swatchFunc = swatchFunc,
            cancelFunc = cancelFunc,
        })
    else
        ColorPickerFrame:Hide()
        ColorPickerFrame.func = nil
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.opacityFunc = nil
        ColorPickerFrame.previousValues = prev
        ColorPickerFrame:SetColorRGB(color.r, color.g, color.b)
        ColorPickerFrame.func = swatchFunc
        ColorPickerFrame.cancelFunc = cancelFunc
        ColorPickerFrame:Show()
    end
end

---------------------------------------------------------------------------
-- Dropdown menu (one shared popup list, owned entirely by this addon)
---------------------------------------------------------------------------

local ROW_HEIGHT = 20
local menu, catcher

-- Always sets the font explicitly: once SetFont has been used on a
-- FontString, SetFontObject no longer reliably resets it.
local function SetFontOrDefault(fontString, path, size)
    if path and fontString:SetFont(path, size, "") then return end
    fontString:SetFont((GameFontHighlight:GetFont()), size, "")
end

local function CloseMenu()
    if menu then
        menu:Hide()
        catcher:Hide()
    end
end

local function CreateMenu()
    -- Invisible full-screen button behind the menu: clicking outside closes it.
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(1)
    catcher:SetScript("OnClick", CloseMenu)
    catcher:Hide()

    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(10)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()

    local border = menu:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.5, 0.5, 1)
    local bg = menu:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)

    menu.rows = {}
end

local function GetMenuRow(i)
    local row = menu.rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(14, 14)
    row.check:SetPoint("LEFT", 4, 0)
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", 22, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")

    menu.rows[i] = row
    return row
end

-- items: { { name = ..., value = ..., font = optional path }, ... }
local function OpenMenu(owner, items, current, onSelect)
    if not menu then CreateMenu() end

    local width = owner:GetWidth()
    for i, item in ipairs(items) do
        local row = GetMenuRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * ROW_HEIGHT)
        row:SetWidth(width - 2)
        SetFontOrDefault(row.text, item.font, 14)
        row.text:SetText(item.name)
        row.check:SetShown(item.value == current)
        row:SetScript("OnClick", function()
            CloseMenu()
            onSelect(item.value)
        end)
        row:Show()
    end
    for i = #items + 1, #menu.rows do
        menu.rows[i]:Hide()
    end

    menu:SetSize(width, #items * ROW_HEIGHT + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    catcher:Show()
    menu:Show()
end

---------------------------------------------------------------------------
-- Widget builders
---------------------------------------------------------------------------

local function Header(text, x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

-- A mock action button with a clickable dot at each corner, edge and center.
local POSITION_LABELS = {
    TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}

local function PositionPicker(x, y)
    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("TOPLEFT", x + 8, y - 8)
    icon:SetTexture(PREVIEW_ICON_BRIGHT)
    icon:SetDesaturated(true)
    icon:SetAlpha(0.5)

    for pos in pairs(ns.POSITIONS) do
        local dot = CreateFrame("Button", nil, panel)
        dot:SetSize(14, 14)
        dot:SetPoint("CENTER", icon, pos, 0, 0)
        dot:SetFrameLevel(panel:GetFrameLevel() + 2)

        local border = dot:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0, 0, 0, 1)
        local fill = dot:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 2, -2)
        fill:SetPoint("BOTTOMRIGHT", -2, 2)
        dot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        dot:SetScript("OnClick", function()
            ns.db.position = pos
            OnSettingChanged()
        end)
        dot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(POSITION_LABELS[pos])
            GameTooltip:Show()
        end)
        dot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        function dot:Refresh()
            if ns.db.position == pos then
                fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            else
                fill:SetColorTexture(0.45, 0.45, 0.45, 1)
            end
        end
        table.insert(widgets, dot)
    end
end

-- A button showing the current choice; clicking it opens the shared menu.
-- items: { { name = ..., value = ..., font = optional path }, ... }
-- Entries with a `font` (and the button, when showing one) are drawn in it;
-- others use the standard UI font.
local function Dropdown(x, y, width, items, key)
    local btn = CreateFrame("Button", nil, panel)
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", x, y)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.5, 0.5, 1)
    local bg = btn:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.05, 0.05, 0.05, 1)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")

    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(20, 20)
    arrow:SetPoint("RIGHT", -2, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

    local text = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    text:SetJustifyH("LEFT")

    local function Normalize(v)
        return type(v) == "string" and v:lower() or v
    end

    local function FindItem(value)
        for _, item in ipairs(items) do
            if Normalize(item.value) == Normalize(value) then return item end
        end
    end

    btn:SetScript("OnClick", function(self)
        local current = FindItem(ns.db[key])
        OpenMenu(self, items, current and current.value, function(value)
            ns.db[key] = value
            OnSettingChanged()
        end)
    end)

    function btn:Refresh()
        local item = FindItem(ns.db[key])
        SetFontOrDefault(text, item and item.font, 14)
        text:SetText(item and item.name or "?")
    end
    table.insert(widgets, btn)
end

-- isDisabled: optional function; when it returns true the slider is dimmed.
local function Slider(labelPrefix, key, minValue, maxValue, x, y, isDisabled)
    local title = Header("", x, y)

    local slider = CreateFrame("Slider", nil, panel)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(180, 17)
    slider:SetPoint("TOPLEFT", x, y - 22)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:EnableMouseWheel(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)
    track:SetColorTexture(0.15, 0.15, 0.15, 1)

    local low = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    low:SetText(minValue)
    local high = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    high:SetText(maxValue)

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= ns.db[key] then
            ns.db[key] = value
            OnSettingChanged()
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta)
    end)

    function slider:Refresh()
        title:SetText(labelPrefix .. ns.db[key])
        self:SetValue(ns.db[key])
        local alpha = (isDisabled and isDisabled()) and 0.4 or 1
        self:SetAlpha(alpha)
        title:SetAlpha(alpha)
    end
    table.insert(widgets, slider)
end

local function ColorSwatch(label, key, x, y)
    local btn = CreateFrame("Button", nil, panel)
    btn:SetSize(20, 20)
    btn:SetPoint("TOPLEFT", x, y)

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.8, 0.8, 0.8, 1)
    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)

    local text = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    text:SetText(label)
    btn:SetHitRectInsets(0, -(text:GetStringWidth() + 10), 0, 0)

    btn:SetScript("OnClick", function()
        OpenColorPicker(key, OnSettingChanged)
    end)

    function btn:Refresh()
        local c = ns.db[key]
        fill:SetColorTexture(c.r, c.g, c.b, 1)
    end
    table.insert(widgets, btn)
end

local function Checkbox(label, key, x, y)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb:SetHitRectInsets(0, -(text:GetStringWidth() + 10), 0, 0)

    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        OnSettingChanged()
    end)

    function cb:Refresh()
        self:SetChecked(ns.db[key])
    end
    table.insert(widgets, cb)
end

-- Fake action buttons showing a lower rank and the highest rank, each on
-- a bright and a dark icon.
local function Preview(x, y)
    local function FakeButton(offsetX, rank, isLower, icon)
        local f = CreateFrame("Frame", nil, panel)
        f:SetSize(36, 36)
        f:SetPoint("TOPLEFT", x + offsetX, y)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(icon)

        local label = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        function f:Refresh()
            ns.StyleLabel(label, f)
            ns.PaintLabel(label, rank, isLower)
        end
        table.insert(widgets, f)
    end
    FakeButton(0,   "1", true,  PREVIEW_ICON_BRIGHT)
    FakeButton(46,  "2", false, PREVIEW_ICON_BRIGHT)
    FakeButton(92,  "1", true,  PREVIEW_ICON_DARK)
    FakeButton(138, "2", false, PREVIEW_ICON_DARK)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function ResetToDefaults()
    ns.ResetSettings()
    OnSettingChanged()
end

function ns.CreateOptions()
    if panel then return end

    panel = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer or UIParent)
    panel.name = PANEL_NAME
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PANEL_NAME)

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Shows spell ranks on your action buttons. Changes apply immediately.")

    local fontItems = {}
    for _, font in ipairs(ns.FONTS) do
        table.insert(fontItems, { name = font.name, value = font.path, font = font.path })
    end

    -- Left column
    Header("Position", 16, -64)
    PositionPicker(16, -84)

    Slider("Padding: ", "padding", 0, 10, 16, -170,
        function() return ns.db.position == "CENTER" end)

    Header("Font", 16, -230)
    Dropdown(16, -250, 180, fontItems, "font")

    Slider("Font size: ", "fontSize", ns.FONT_SIZE_MIN, ns.FONT_SIZE_MAX, 16, -290)

    Header("Outline", 16, -350)
    Dropdown(16, -370, 180, ns.OUTLINES, "outline")

    Checkbox("Shadow", "shadow", 12, -400)

    -- Right column
    Header("Preview", 300, -64)
    Preview(300, -88)

    Header("Colors", 300, -150)
    ColorSwatch("Lower rank", "lowerColor", 300, -172)
    ColorSwatch("Highest known rank", "highestColor", 300, -200)

    Checkbox("Show number on highest known rank", "showHighest", 296, -232)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetPoint("TOPLEFT", 16, -450)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", ResetToDefaults)

    panel:SetScript("OnShow", RefreshWidgets)
    panel:SetScript("OnHide", CloseMenu)
    -- Blizzard's "Defaults" button (new and old settings UIs).
    panel.OnDefault = ResetToDefaults
    panel.default = ResetToDefaults

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
        Settings.RegisterAddOnCategory(category)
        ns.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

---------------------------------------------------------------------------
-- /srd opens the panel
---------------------------------------------------------------------------

SLASH_SPELLRANKDISPLAY1 = "/srd"
SlashCmdList.SPELLRANKDISPLAY = function()
    if ns.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice to work around a long-standing Blizzard bug.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
