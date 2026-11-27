--[[---------------------------------------------------------------------------
    NanoCopy - copy a chat line straight from the player-name menu
    Target client: World of Warcraft: Forever ("wowf", interface 16001)

    Right-click a player name inside a chat frame. The retail unit menu that
    the client opens already carries our entries (Menu.ModifyMenu on
    MENU_UNIT_PLAYER, which - as the Spy addon documents - also covers chat
    names), and we offer:

        * copy this message line (links and colour codes stripped)
        * copy the plain player name

    Clipboard: the client has no documented write API, so we try the two
    candidates that exist in the wild (SetClipboardText / C_Clipboard.SetText)
    and fall back to a pre-selected edit box where the user just presses Ctrl+C.
-----------------------------------------------------------------------------]]

local ADDON = ...

local LOCALE = (GetLocale and GetLocale()) or "enUS"
local L
if LOCALE == "zhCN" then
	L = {
		title = "NanoCopy",
		copyLine = "复制这一行",
		copied = "已复制到剪贴板",
		boxHint = "已选中文本，按 Ctrl+C 复制（Esc 关闭）",
	}
elseif LOCALE == "zhTW" then
	L = {
		title = "NanoCopy",
		copyLine = "複製這一行",
		copied = "已複製到剪貼簿",
		boxHint = "已選中文字，按 Ctrl+C 複製（Esc 關閉）",
	}
else
	L = {
		title = "NanoCopy",
		copyLine = "Copy this line",
		copied = "Copied to clipboard",
		boxHint = "Text selected - press Ctrl+C to copy (Esc to close)",
	}
end

local COLOR = "|cff46bf72"
local RESET = "|r"

local function Tell(text)
	if type(text) ~= "string" or text == "" then return end
	local frame = DEFAULT_CHAT_FRAME or ChatFrame1
	if frame and frame.AddMessage then
		frame:AddMessage(COLOR .. "[" .. L.title .. "]|r " .. text)
	elseif print then
		print("[" .. L.title .. "] " .. text)
	end
end

-- ---------------------------------------------------------------- clipboard --

local function CopyToClipboard(text)
	if type(text) ~= "string" or text == "" then return false end
	if type(SetClipboardText) == "function" then
		if pcall(SetClipboardText, text) then return true end
	end
	if type(C_Clipboard) == "table" and type(C_Clipboard.SetText) == "function" then
		if pcall(C_Clipboard.SetText, text) then return true end
	end
	return false
end

local copyBox

local function EnsureCopyBox()
	if copyBox then return copyBox end
	local frame = CreateFrame("Frame", "CopyFromChatBox", UIParent, "BackdropTemplate")
	frame:SetSize(520, 150)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.85)
		frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	end

	local editBox = CreateFrame("EditBox", nil, frame)
	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetMaxLetters(0)
	editBox:SetFontObject(ChatFontNormal or GameFontHighlight)
	if editBox.SetJustifyH then editBox:SetJustifyH("LEFT") end
	if editBox.SetJustifyV then editBox:SetJustifyV("TOP") end
	editBox:SetPoint("TOPLEFT", 14, -14)
	editBox:SetPoint("BOTTOMRIGHT", -14, 30)
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		frame:Hide()
	end)
	frame.editBox = editBox

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOP", 0, -8)
	title:SetText(L.title)
	frame.title = title

	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 14, 10)
	hint:SetText(L.boxHint)
	frame.hint = hint

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	copyBox = frame
	return frame
end

local function ShowCopyBox(text)
	local frame = EnsureCopyBox()
	frame.editBox:SetText(text or "")
	frame:Show()
	frame:Raise()
	frame.editBox:SetFocus()
	frame.editBox:HighlightText()
end

local function CopyText(text)
	if type(text) ~= "string" or text == "" then return end
	if CopyToClipboard(text) then
		Tell(L.copied)
	else
		ShowCopyBox(text)
	end
end

-- ---------------------------------------------------------------- chat text --

-- Strip colour codes, links (keep their display text), textures and atlas
-- tags so the pasted text is plain and readable.
local function CleanText(text)
	if type(text) ~= "string" then return "" end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
	text = text:gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("|A.-|a", "")
	text = text:gsub("|T.-|t", "")
	text = text:gsub("||", "|")
	return text
end

-- Find the chat line that produced the clicked link. GetMessageInfo returns the
-- full line text first, which is what the retail client exposes per line.
local function FindLine(chatFrame, link)
	if not chatFrame or type(chatFrame.GetNumMessages) ~= "function" or type(chatFrame.GetMessageInfo) ~= "function" then
		return nil
	end
	local linkText = type(link) == "string" and link or ""
	local total = chatFrame:GetNumMessages() or 0
	if total <= 0 then return nil end
	local lowest = math.max(1, total - 300)
	for i = total, lowest, -1 do
		local ok, text = pcall(chatFrame.GetMessageInfo, chatFrame, i)
		if ok and type(text) == "string" then
			if linkText ~= "" and text:find(linkText, 1, true) then
				return text, i
			end
		end
	end
	return nil
end

-- The link is "player:Name", "player:Name:realm" or "BNplayer:Name:BNid"; the
-- clicked display text is the plain name, which is the safest fallback.
local function NameFromLink(link, displayText)
	if type(link) == "string" then
		local name = link:match("^player:([^:]+)") or link:match("^BNplayer:([^:]+)")
		if name and name ~= "" then return name end
	end
	if type(displayText) == "string" and displayText ~= "" then
		return CleanText(displayText)
	end
	return nil
end

-- ------------------------------------------------------------------- menu ----

-- Set by the chat hyperlink hook right before the client opens the unit menu.
local lastChatClick

local function CopyLastLine()
	local click = lastChatClick
	if not click then return end
	local line = FindLine(click.frame, click.link)
	CopyText(CleanText(line or click.text))
end

-- A chat name does not use MENU_UNIT_PLAYER: the retail client routes it
-- through the roster/chat menus. Spy (which works on Forever) registers the
-- whole family, so we mirror that list - missing CHAT_ROSTER was exactly why
-- no entry appeared on right-clicking a name in the chat frame.
local MENU_TAGS = {
	"PLAYER", "TARGET", "FOCUS", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "ENEMY_PLAYER",
	"CHAT_ROSTER", "COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER", "GUILD",
}

-- How long a recorded chat hyperlink click stays relevant for the menu.
local CLICK_TTL = 10

-- Only the message line is offered: copying the player name is already built
-- into the client's own unit menu.
local function AddMenuEntries(owner, rootDescription)
	if type(rootDescription) ~= "table" or type(rootDescription.CreateButton) ~= "function" then return end

	local click = lastChatClick
	local now = (GetTime and GetTime()) or 0
	if type(click) ~= "table" or (now - (click.time or 0)) > CLICK_TTL then return end

	rootDescription:CreateDivider()
	if type(rootDescription.CreateTitle) == "function" then
		rootDescription:CreateTitle(L.title)
	end
	rootDescription:CreateButton(L.copyLine, CopyLastLine)
end

if Menu and type(Menu.ModifyMenu) == "function" then
	for _, tag in ipairs(MENU_TAGS) do
		pcall(Menu.ModifyMenu, "MENU_UNIT_" .. tag, AddMenuEntries)
	end
end

-- ------------------------------------------------------------- chat hooks ----

local function OnHyperlinkClick(chatFrame, link, text, button)
	if button ~= "RightButton" then return end
	lastChatClick = {
		frame = chatFrame,
		link = link,
		text = text,
		time = (GetTime and GetTime()) or 0,
	}
end

local function HookChatFrames()
	local count = _G.NUM_CHAT_WINDOWS or 10
	for i = 1, count do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame and chatFrame.HookScript then
			pcall(chatFrame.HookScript, chatFrame, "OnHyperlinkClick", OnHyperlinkClick)
		end
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	HookChatFrames()
end)

-- --------------------------------------------------------------- slash cmd ---

SLASH_NANOCOPY1 = "/nanocopy"
SlashCmdList["NANOCOPY"] = function(msg)
	local arg = type(msg) == "string" and msg:lower():match("^%s*(.-)%s*$") or ""
	if arg == "test" then
		CopyText("NanoCopy clipboard test")
		return
	end
	Tell("Menu.ModifyMenu: " .. tostring(Menu ~= nil and type(Menu.ModifyMenu) == "function"))
	Tell("menu tags registered: " .. tostring(#MENU_TAGS))
	local click = lastChatClick
	if click then
		local frameName = click.frame and click.frame.GetName and click.frame:GetName() or "?"
		Tell("last chat click: " .. tostring(click.link) .. " on " .. tostring(frameName) .. " (" ..
			string.format("%.0fs ago", ((GetTime and GetTime()) or 0) - (click.time or 0)) .. ")")
	else
		Tell("last chat click: none (right-click a chat name once)")
	end
	Tell("/nanocopy test - verify the clipboard path")
end
