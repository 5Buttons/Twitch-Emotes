-- Access the window by shift-clicking the minimap button.

TwitchEmoteStatistics = TwitchEmoteStatistics or {}

-- Tracking 

function TwitchEmotes_UpdateStats(emote, isSent)
    if not defaultpack[emote] then return end
    if not TwitchEmoteStatistics[emote] then
        TwitchEmoteStatistics[emote] = { 0, 0 }  -- { sent, seen }
    end
    local s = TwitchEmoteStatistics[emote]
    if isSent then s[1] = s[1] + 1 else s[2] = s[2] + 1 end
end

local texToEmote = nil
local function buildTexLookup()
    texToEmote = {}
    for emote, path in pairs(defaultpack) do
        local tga = path:match("(.*%.tga)")
        if tga then texToEmote[tga] = emote end
    end
end

function Emoticons_MessageFilter(self, event, msg, ...)
    local sender = select(1, ...)
    local isSelf = (sender == UnitName("player"))
    local processed = Emoticons_RunReplacement(msg)
    if processed ~= msg then
        if not texToEmote then buildTexLookup() end
        local counted = {}
        for texPath in processed:gmatch("|T(.-)|t") do
            local tga = texPath:match("(.*%.tga)")
            if tga then
                local emote = texToEmote[tga]
                if emote and not counted[emote] then
                    TwitchEmotes_UpdateStats(emote, isSelf)
                    counted[emote] = true
                end
            end
        end
    end
    return false, processed, ...
end

-- ── Stats window

local NUM_LINES = 14
local LINE_H    = 20
local WIN_W     = 590
local WIN_H     = 390

local sentKeys  = {}
local seenKeys  = {}
local sentLines = {}
local seenLines = {}
local statsWin  = nil

local function refreshKeys()
    sentKeys, seenKeys = {}, {}
    for emote, stats in pairs(TwitchEmoteStatistics) do
        if defaultpack[emote] then
            if stats[1] > 0 then sentKeys[#sentKeys + 1] = emote end
            if stats[2] > 0 then seenKeys[#seenKeys + 1] = emote end
        end
    end
    table.sort(sentKeys, function(a, b)
        return TwitchEmoteStatistics[a][1] > TwitchEmoteStatistics[b][1]
    end)
    table.sort(seenKeys, function(a, b)
        return TwitchEmoteStatistics[a][2] > TwitchEmoteStatistics[b][2]
    end)
end

local function updateList(lines, sf, keys, statIdx)
    local offset = FauxScrollFrame_GetOffset(sf)
    FauxScrollFrame_Update(sf, #keys, NUM_LINES, LINE_H)
    for i = 1, NUM_LINES do
        local idx  = i + offset
        local line = lines[i]
        if idx <= #keys then
            local emote = keys[idx]
            local entry = defaultpack[emote]
            local tex   = entry and entry:match("(.*%.tga)")
            if tex then line.ico:SetTexture(tex); line.ico:Show()
            else        line.ico:Hide() end
            line.lbl:SetText(string.format(
                "|cffFFD700%d.|r %s |cff00FF00x%d|r",
                idx, emote, TwitchEmoteStatistics[emote][statIdx]
            ))
            line:Show()
        else
            line:Hide()
        end
    end
end

local function makeLineEntries(parent, xOff, yOff, lineTable, colW)
    for i = 1, NUM_LINES do
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(colW, LINE_H)
        row:SetPoint("TOPLEFT", xOff, yOff - (i - 1) * LINE_H)

        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(16, 16)
        ico:SetPoint("LEFT", 0, 0)
        row.ico = ico

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", ico, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        row.lbl = lbl

        row:Hide()
        lineTable[i] = row
    end
end

local function buildWindow()
    local f = CreateFrame("Frame", "TwitchEmotesStatsFrame", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Emote Statistics")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", 0, -36)
    hint:SetTextColor(0.55, 0.55, 0.55)
    hint:SetText("Shift-click the minimap button to toggle  \226\128\162  Drag to move")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() f:Hide() end)

    local colW  = math.floor((WIN_W - 68) / 2)
    local listY = -72
    local leftX = 16
    local rightX = leftX + colW + 36

    local sh = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sh:SetPoint("TOPLEFT", leftX, -54)
    sh:SetText("|cff9999ffSent by you|r")

    local vh = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    vh:SetPoint("TOPLEFT", rightX, -54)
    vh:SetText("|cff9999ffSeen in chat|r")

    local div = f:CreateTexture(nil, "BACKGROUND")
    div:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    div:SetSize(1, NUM_LINES * LINE_H + 10)
    div:SetPoint("TOPLEFT", leftX + colW + 17, listY + 4)

    makeLineEntries(f, leftX,  listY, sentLines, colW)
    makeLineEntries(f, rightX, listY, seenLines, colW)

    local sentSF = CreateFrame("ScrollFrame", "TwitchEmotesStatsSentSF", f, "FauxScrollFrameTemplate")
    sentSF:SetSize(colW + 16, NUM_LINES * LINE_H)
    sentSF:SetPoint("TOPLEFT", leftX - 1, listY + 1)
    sentSF:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, LINE_H, function()
            updateList(sentLines, self, sentKeys, 1)
        end)
    end)

    local seenSF = CreateFrame("ScrollFrame", "TwitchEmotesStatsSeenSF", f, "FauxScrollFrameTemplate")
    seenSF:SetSize(colW + 16, NUM_LINES * LINE_H)
    seenSF:SetPoint("TOPLEFT", rightX - 1, listY + 1)
    seenSF:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, LINE_H, function()
            updateList(seenLines, self, seenKeys, 2)
        end)
    end)

    f.sentSF = sentSF
    f.seenSF = seenSF
    f:Hide()
    return f
end

function TwitchStats_Toggle()
    if not statsWin then
        statsWin = buildWindow()
    end
    if statsWin:IsShown() then
        statsWin:Hide()
    else
        refreshKeys()
        updateList(sentLines, statsWin.sentSF, sentKeys, 1)
        updateList(seenLines, statsWin.seenSF, seenKeys, 2)
        statsWin:Show()
    end
end
