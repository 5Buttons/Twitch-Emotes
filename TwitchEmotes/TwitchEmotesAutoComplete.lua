local MAX_SUGGESTIONS = 10
local BTN_H           = 22
local POPUP_W         = 250
local MIN_CHARS       = 2     -- characters required after the ':' before showing

local allNames       = nil    -- sorted list of all emote codes, built lazily
local activeBox      = nil    -- the edit box currently driving the popup
local acToken        = ""     -- the trailing ":query" token being completed
local currentResults = nil    -- list of suggestion strings currently shown
local selIndex       = 1      -- highlighted suggestion (1-based)
local visibleCount   = 0      -- number of suggestion buttons currently shown
local suppress       = false  -- guard against our own SetText re-triggering
local applySelection          -- forward declaration (used by button OnClick)

local function buildNames()
    allNames = {}
    for k in pairs(emoticons) do
        allNames[#allNames + 1] = k
    end
    table.sort(allNames)
end

-- true if every char of q appears in name in order (not necessarily contiguous)
local function isSubsequence(name, q)
    local qlen = #q
    if qlen == 0 then return false end
    local qi = 1
    for ci = 1, #name do
        if name:sub(ci, ci) == q:sub(qi, qi) then
            qi = qi + 1
            if qi > qlen then return true end
        end
    end
    return false
end

-- Ranked match: exact prefix first, then substring, then fuzzy subsequence.
local function filterEmotes(query)
    if not allNames then buildNames() end
    local lq   = query:lower()
    local out  = {}
    local seen = {}
    -- 1. prefix matches
    for _, n in ipairs(allNames) do
        if n:lower():sub(1, #lq) == lq then
            out[#out + 1] = n; seen[n] = true
            if #out >= MAX_SUGGESTIONS then return out end
        end
    end
    -- 2. substring matches
    for _, n in ipairs(allNames) do
        if not seen[n] and n:lower():find(lq, 1, true) then
            out[#out + 1] = n; seen[n] = true
            if #out >= MAX_SUGGESTIONS then return out end
        end
    end
    -- 3. fuzzy (subsequence) matches
    for _, n in ipairs(allNames) do
        if not seen[n] and isSubsequence(n:lower(), lq) then
            out[#out + 1] = n; seen[n] = true
            if #out >= MAX_SUGGESTIONS then return out end
        end
    end
    return out
end

-- ── Popup frame ──────────────────────────────────────────────────────────────

local popup = CreateFrame("Frame", "TwitchEmotesACPopup", UIParent)
popup:SetWidth(POPUP_W)
popup:SetFrameStrata("TOOLTIP")
popup:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
popup:Hide()

local btns = {}
for i = 1, MAX_SUGGESTIONS do
    local idx = i
    local b = CreateFrame("Button", nil, popup)
    b:SetHeight(BTN_H)
    b:SetPoint("TOPLEFT", 3, -(i - 1) * BTN_H - 3)
    b:SetPoint("RIGHT", -3, 0)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local ico = b:CreateTexture(nil, "ARTWORK")
    ico:SetSize(16, 16)
    ico:SetPoint("LEFT", 2, 0)
    b.ico = ico

    local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", ico, "RIGHT", 4, 0)
    lbl:SetPoint("RIGHT", -2, 0)
    lbl:SetJustifyH("LEFT")
    b.lbl = lbl

    b:SetScript("OnClick", function()
        selIndex = idx
        applySelection()
    end)

    b:Hide()
    btns[i] = b
end

-- ── Show / hide / select helpers ───────────────────────────────────────────────

local function hidePopup()
    popup:Hide()
    activeBox      = nil
    currentResults = nil
    visibleCount   = 0
    selIndex       = 1
end

local function setSelection(i)
    if visibleCount == 0 then return end
    if i < 1 then
        i = visibleCount
    elseif i > visibleCount then
        i = 1
    end
    selIndex = i
    for k = 1, MAX_SUGGESTIONS do
        if k == selIndex then
            btns[k]:LockHighlight()
        else
            btns[k]:UnlockHighlight()
        end
    end
end

local function showPopup(eb, results)
    if #results == 0 then hidePopup(); return end
    activeBox      = eb
    currentResults = results
    local n = math.min(#results, MAX_SUGGESTIONS)
    visibleCount = n
    popup:SetHeight(n * BTN_H + 6)
    for i = 1, MAX_SUGGESTIONS do
        local b = btns[i]
        if i <= n then
            local name = results[i]
            b.lbl:SetText(name)
            -- icon: look up via emoticons map, fall back to direct defaultpack key
            local key   = emoticons[name] or name
            local entry = defaultpack[key]
            local tex   = entry and entry:match("(.*%.tga)")
            if tex then b.ico:SetTexture(tex); b.ico:Show()
            else        b.ico:Hide() end
            b:Show()
        else
            b:Hide()
        end
    end
    popup:ClearAllPoints()
    popup:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 4)
    popup:Show()
    setSelection(1)
end

applySelection = function()
    local box = activeBox
    if box and currentResults and currentResults[selIndex] then
        local emote   = currentResults[selIndex]
        local t       = box:GetText()
        -- replace the trailing ":query" token with the selected emote + space
        local newText = t:sub(1, #t - #acToken) .. emote .. " "
        suppress = true
        box:SetText(newText)
        box:SetCursorPosition(#newText)
        suppress = false
        box:SetFocus()
    end
    hidePopup()
end

-- ── Edit box hook ─────────────────────────────────────────────────────────────

local function onTextChanged(self)
    if suppress then return end
    if not Emoticons_Settings["AUTOCOMPLETE"] then hidePopup(); return end
    local text  = self:GetText()
    -- trailing run starting at the last ':' with no whitespace after it
    local token = text:match("(:[^%s]*)$")
    if token then
        local query = token:sub(2)
        -- a second ':' means the term is "closed" (e.g. ":poop:") -> don't suggest
        if not query:find(":", 1, true) and #query >= MIN_CHARS then
            local results = filterEmotes(query)
            if #results > 0 then
                acToken = token
                showPopup(self, results)
                return
            end
        end
    end
    hidePopup()
end

local hooked = {}
local function hookEditBox(eb)
    if not eb or hooked[eb] then return end
    hooked[eb] = true

    eb:HookScript("OnTextChanged", onTextChanged)
    eb:HookScript("OnHide",        hidePopup)

    -- Enter: when the popup is open, apply the highlighted suggestion instead of
    -- sending the message. Otherwise fall through to the original handler.
    local origEnter = eb:GetScript("OnEnterPressed")
    eb:SetScript("OnEnterPressed", function(self, ...)
        if popup:IsShown() then
            applySelection()
            return
        end
        if origEnter then return origEnter(self, ...) end
    end)

    -- Escape: when the popup is open, just close it (don't close the edit box).
    local origEsc = eb:GetScript("OnEscapePressed")
    eb:SetScript("OnEscapePressed", function(self, ...)
        if popup:IsShown() then
            hidePopup()
            return
        end
        if origEsc then return origEsc(self, ...) end
    end)

    -- Tab / Shift-Tab: cycle the highlighted suggestion while the popup is open;
    -- otherwise fall through to the default (channel / name completion).
    local origTab = eb:GetScript("OnTabPressed")
    eb:SetScript("OnTabPressed", function(self, ...)
        if popup:IsShown() then
            setSelection(selIndex + (IsShiftKeyDown() and -1 or 1))
            return
        end
        if origTab then return origTab(self, ...) end
    end)
end

-- Hook all chat edit boxes once the player enters the world
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        hookEditBox(_G["ChatFrame" .. i .. "EditBox"])
    end
end)
