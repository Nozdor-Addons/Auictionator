-- Вкладка «Списки покупок» в окне аукциона NOZDOR (Custom_AuctionHouseUI).
--
-- Списки общие со стоковым Auctionator: AUCTIONATOR_SHOPPING_LISTS, записи
-- { name, items, isRecents }. Поиск по списку — по одному запросу обзора на
-- предмет; строки результатов открывают стоковую покупку нового окна.

if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and AuctionHouseFrame
	and AuctionHouseFrame.Tabs and AuctionHouseFrameDisplayMode) then
	return;
end

local MODE = "AuctionatorShopping";
local FRAME_KEY = "AuctionatorShopFrame";

local ROW_HEIGHT = 20;
local LIST_ROWS = 16;
local RESULT_ROWS = 20;
local LEFT_WIDTH = 240;
local QUERY_TIMEOUT = 8;

local ahFrame = AuctionHouseFrame;

local currentListIndex = 1;
local results = {};
local search = { queue = nil, total = 0, done = 0, waitingSince = nil, savedHistory = nil };

-----------------------------------------
-- Списки
-----------------------------------------

local function SortLists(x, y)
	if x.isRecents then return true; end
	if y.isRecents then return false; end
	return string.lower(x.name) < string.lower(y.name);
end

local function GetLists()
	if type(AUCTIONATOR_SHOPPING_LISTS) ~= "table" then
		AUCTIONATOR_SHOPPING_LISTS = {};
	end

	if #AUCTIONATOR_SHOPPING_LISTS == 0 then
		table.insert(AUCTIONATOR_SHOPPING_LISTS, { name = ZT("Recent Searches"), items = {}, isRecents = 1 });
	end

	return AUCTIONATOR_SHOPPING_LISTS;
end

local function GetCurrentList()
	local lists = GetLists();
	if currentListIndex > #lists then
		currentListIndex = 1;
	end
	return lists[currentListIndex];
end

local function SelectListByTable(list)
	for index, candidate in ipairs(GetLists()) do
		if candidate == list then
			currentListIndex = index;
			return;
		end
	end
end

-----------------------------------------
-- Каркас вкладки
-----------------------------------------

local frame = CreateFrame("Frame", "AuctionatorNozdorShopFrame", ahFrame);
frame:SetPoint("LEFT", ahFrame, "LEFT", 5, 0);
frame:SetPoint("RIGHT", ahFrame, "RIGHT", -3, 0);
frame:SetPoint("TOP", ahFrame, "TOP", 0, -42);
frame:SetPoint("BOTTOM", ahFrame.MoneyFrameBorder, "TOP", 0, 2);
frame:Hide();

ahFrame[FRAME_KEY] = frame;
AuctionHouseFrameDisplayMode[MODE] = { FRAME_KEY };

local leftPanel = CreateFrame("Frame", nil, frame, "InsetFrameTemplate");
leftPanel:SetPoint("TOPLEFT");
leftPanel:SetPoint("BOTTOMLEFT");
leftPanel:SetWidth(LEFT_WIDTH);

local rightPanel = CreateFrame("Frame", nil, frame, "InsetFrameTemplate");
rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 4, 0);
rightPanel:SetPoint("BOTTOMRIGHT");

local function CreateButton(parent, width, text)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate");
	button:SetSize(width, 22);
	button:SetText(text);
	return button;
end

-----------------------------------------
-- Левая часть: выбор списка и его предметы
-----------------------------------------

local UpdateItemList;
local StartSearch;

local listDropDown = CreateFrame("Frame", "AuctionatorNozdorShopListDropDown", leftPanel, "UIDropDownMenuTemplate");
listDropDown:SetPoint("TOPLEFT", -8, -6);
UIDropDownMenu_SetWidth(listDropDown, LEFT_WIDTH - 40);

local function ListDropDown_Initialize()
	for index, list in ipairs(GetLists()) do
		local info = UIDropDownMenu_CreateInfo();
		info.text = list.name;
		info.checked = index == currentListIndex;
		info.func = function()
			currentListIndex = index;
			UpdateItemList();
		end;
		UIDropDownMenu_AddButton(info);
	end
end

local newListButton = CreateButton(leftPanel, 110, ZT("New list"));
newListButton:SetPoint("TOPLEFT", 10, -40);

local deleteListButton = CreateButton(leftPanel, 110, ZT("Delete list"));
deleteListButton:SetPoint("LEFT", newListButton, "RIGHT", 2, 0);

local addBox = CreateFrame("EditBox", "AuctionatorNozdorShopAddBox", leftPanel, "InputBoxTemplate");
addBox:SetSize(LEFT_WIDTH - 92, 20);
addBox:SetPoint("TOPLEFT", 16, -70);
addBox:SetAutoFocus(false);

local addButton = CreateButton(leftPanel, 64, ZT("Add"));
addButton:SetPoint("LEFT", addBox, "RIGHT", 4, 0);

local addHint = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
addHint:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -4, -2);
addHint:SetWidth(LEFT_WIDTH - 20);
addHint:SetJustifyH("LEFT");
addHint:SetText(ZT("Type an item name or Shift-click an item"));

local itemsScroll = CreateFrame("ScrollFrame", "AuctionatorNozdorShopItemsScroll", leftPanel, "FauxScrollFrameTemplate");
itemsScroll:SetPoint("TOPLEFT", 8, -108);
itemsScroll:SetPoint("RIGHT", leftPanel, "RIGHT", -28, 0);
itemsScroll:SetHeight(LIST_ROWS * ROW_HEIGHT);

local itemRows = {};
for index = 1, LIST_ROWS do
	local row = CreateFrame("Button", nil, leftPanel);
	row:SetHeight(ROW_HEIGHT);
	row:SetPoint("TOPLEFT", itemsScroll, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT);
	row:SetPoint("RIGHT", itemsScroll, "RIGHT", 0, 0);
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");

	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	row.text:SetPoint("LEFT", 4, 0);
	row.text:SetPoint("RIGHT", -4, 0);
	row.text:SetJustifyH("LEFT");

	itemRows[index] = row;
end

local searchListButton = CreateButton(leftPanel, LEFT_WIDTH - 20, ZT("Search list"));
searchListButton:SetPoint("BOTTOM", 0, 8);

function UpdateItemList()
	local list = GetCurrentList();
	UIDropDownMenu_SetText(listDropDown, list.name);

	local items = list.items;
	if not list.isRecents and not list.isSorted then
		table.sort(items, function(x, y) return string.lower(x) < string.lower(y); end);
		list.isSorted = true;
	end

	FauxScrollFrame_Update(itemsScroll, #items, LIST_ROWS, ROW_HEIGHT);
	local offset = FauxScrollFrame_GetOffset(itemsScroll);

	for index, row in ipairs(itemRows) do
		local itemName = items[offset + index];
		row.itemName = itemName;
		if itemName then
			row.text:SetText(itemName);
			row:Show();
		else
			row:Hide();
		end
	end

	deleteListButton:SetEnabled(not list.isRecents);
	searchListButton:SetEnabled(#items > 0 and not search.queue);
end

itemsScroll:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateItemList);
end);

local function AddItemToCurrentList()
	local itemName = strtrim(addBox:GetText() or "");
	if itemName == "" then
		return;
	end

	local list = GetCurrentList();
	for _, existing in ipairs(list.items) do
		if string.lower(existing) == string.lower(itemName) then
			addBox:SetText("");
			return;
		end
	end

	table.insert(list.items, list.isRecents and 1 or (#list.items + 1), itemName);
	list.isSorted = false;
	addBox:SetText("");
	UpdateItemList();
end

addButton:SetScript("OnClick", AddItemToCurrentList);
addBox:SetScript("OnEnterPressed", function(self)
	AddItemToCurrentList();
	self:ClearFocus();
end);
addBox:SetScript("OnEscapePressed", function(self)
	self:ClearFocus();
end);

-- Shift-клик по предмету, пока поле ввода в фокусе, подставляет его название.
local origChatEditInsertLink = ChatEdit_InsertLink;
ChatEdit_InsertLink = function(text, ...)
	if text and addBox:IsVisible() and addBox:HasFocus() then
		local itemName = GetItemInfo(text);
		if itemName then
			addBox:SetText(itemName);
			return true;
		end
	end
	return origChatEditInsertLink(text, ...);
end;

for _, row in ipairs(itemRows) do
	row:SetScript("OnClick", function(self, button)
		if not self.itemName then
			return;
		end

		if button == "RightButton" then
			local list = GetCurrentList();
			for index, existing in ipairs(list.items) do
				if existing == self.itemName then
					table.remove(list.items, index);
					break;
				end
			end
			UpdateItemList();
		else
			StartSearch({ self.itemName });
		end
	end);

	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:AddLine(self.itemName or "");
		GameTooltip:AddLine(ZT("Left click: search. Right click: remove from list."), 0.8, 0.8, 0.8, true);
		GameTooltip:Show();
	end);
	row:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
end

StaticPopupDialogs["AUCTIONATOR_NOZDOR_NEW_LIST"] = {
	text = ZT("Name of the new shopping list:"),
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 64,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	OnAccept = function(self)
		local name = strtrim(_G[self:GetName().."EditBox"]:GetText() or "");
		if name == "" then
			return;
		end

		local list = { name = name, items = {} };
		local lists = GetLists();
		table.insert(lists, list);
		table.sort(lists, SortLists);
		SelectListByTable(list);
		UpdateItemList();
	end,
	EditBoxOnEnterPressed = function(self)
		local dialog = self:GetParent();
		StaticPopupDialogs["AUCTIONATOR_NOZDOR_NEW_LIST"].OnAccept(dialog);
		dialog:Hide();
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide();
	end,
	OnShow = function(self)
		_G[self:GetName().."EditBox"]:SetText("");
	end,
};

StaticPopupDialogs["AUCTIONATOR_NOZDOR_DELETE_LIST"] = {
	text = ZT("Delete shopping list \"%s\"?"),
	button1 = YES,
	button2 = NO,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	OnAccept = function(self, list)
		local lists = GetLists();
		for index, candidate in ipairs(lists) do
			if candidate == list and not candidate.isRecents then
				table.remove(lists, index);
				break;
			end
		end
		currentListIndex = 1;
		UpdateItemList();
	end,
};

newListButton:SetScript("OnClick", function()
	StaticPopup_Show("AUCTIONATOR_NOZDOR_NEW_LIST");
end);

deleteListButton:SetScript("OnClick", function()
	local list = GetCurrentList();
	if list.isRecents then
		return;
	end
	local dialog = StaticPopup_Show("AUCTIONATOR_NOZDOR_DELETE_LIST", list.name);
	if dialog then
		dialog.data = list;
	end
end);

-----------------------------------------
-- Правая часть: результаты
-----------------------------------------

local statusText = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
statusText:SetPoint("TOPLEFT", 12, -10);
statusText:SetPoint("RIGHT", -12, 0);
statusText:SetJustifyH("LEFT");

local function CreateHeader(text, justify)
	local header = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
	header:SetText(text);
	header:SetJustifyH(justify);
	return header;
end

local resultsScroll = CreateFrame("ScrollFrame", "AuctionatorNozdorShopResultsScroll", rightPanel, "FauxScrollFrameTemplate");
resultsScroll:SetPoint("TOPLEFT", 8, -52);
resultsScroll:SetPoint("RIGHT", rightPanel, "RIGHT", -28, 0);
resultsScroll:SetHeight(RESULT_ROWS * ROW_HEIGHT);

local nameHeader = CreateHeader(ZT("Item Name"), "LEFT");
nameHeader:SetPoint("BOTTOMLEFT", resultsScroll, "TOPLEFT", 26, 4);

local priceHeader = CreateHeader(ZT("Buyout Price"), "RIGHT");
priceHeader:SetPoint("BOTTOMRIGHT", resultsScroll, "TOPRIGHT", -4, 4);

local quantityHeader = CreateHeader(ZT("Available"), "RIGHT");
quantityHeader:SetPoint("BOTTOMRIGHT", resultsScroll, "TOPRIGHT", -150, 4);

local resultRows = {};
for index = 1, RESULT_ROWS do
	local row = CreateFrame("Button", nil, rightPanel);
	row:SetHeight(ROW_HEIGHT);
	row:SetPoint("TOPLEFT", resultsScroll, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT);
	row:SetPoint("RIGHT", resultsScroll, "RIGHT", 0, 0);
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");

	row.icon = row:CreateTexture(nil, "ARTWORK");
	row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2);
	row.icon:SetPoint("LEFT", 2, 0);

	row.price = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	row.price:SetPoint("RIGHT", -4, 0);
	row.price:SetJustifyH("RIGHT");

	row.quantity = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	row.quantity:SetPoint("RIGHT", -150, 0);
	row.quantity:SetJustifyH("RIGHT");

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0);
	row.name:SetPoint("RIGHT", row.quantity, "LEFT", -8, 0);
	row.name:SetJustifyH("LEFT");

	resultRows[index] = row;
end

local function UpdateResults()
	FauxScrollFrame_Update(resultsScroll, #results, RESULT_ROWS, ROW_HEIGHT);
	local offset = FauxScrollFrame_GetOffset(resultsScroll);

	for index, row in ipairs(resultRows) do
		local result = results[offset + index];
		row.result = result;
		if result then
			local info = C_AuctionHouse.GetItemKeyInfo(result.itemKey);
			local color = info and ITEM_QUALITY_COLORS[info.quality or 1];
			row.icon:SetTexture(info and info.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark");
			row.name:SetText(info and ((color and color.hex or "")..info.itemName.."|r") or "...");
			row.quantity:SetText(result.totalQuantity or "");
			row.price:SetText(GetMoneyString(result.minPrice));
			row:Show();
		else
			row:Hide();
		end
	end

	if search.queue then
		statusText:SetText(format(ZT("Searching %d of %d..."), search.done, search.total));
	elseif search.total > 0 then
		statusText:SetText(#results > 0 and format(ZT("Found: %d"), #results) or ZT("Nothing found"));
	else
		statusText:SetText("");
	end
end

resultsScroll:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateResults);
end);

for _, row in ipairs(resultRows) do
	row:SetScript("OnClick", function(self)
		-- Без информации о предмете стоковый SelectBrowseResult падает.
		if self.result and ahFrame.SelectBrowseResult and C_AuctionHouse.GetItemKeyInfo(self.result.itemKey) then
			ahFrame:SelectBrowseResult(self.result);
		end
	end);

	row:SetScript("OnEnter", function(self)
		if self.result then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetHyperlink(format("item:%d:0:0:0:0:0:%d", self.result.itemKey.itemID, self.result.itemKey.itemSuffix or 0));
			GameTooltip:Show();
		end
	end);
	row:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
end

-----------------------------------------
-- Поиск по списку
-----------------------------------------

-- Каждый запрос обзора клиент записывает в историю поиска аукциона; предметы
-- списка туда не должны попадать.
local function RestoreSearchHistory()
	if search.savedHistory and type(AH_SEARCH_HISTORY) == "table" then
		table.wipe(AH_SEARCH_HISTORY);
		for index, text in ipairs(search.savedHistory) do
			AH_SEARCH_HISTORY[index] = text;
		end
		if AuctionHouseCache_Save then
			AuctionHouseCache_Save();
		end
	end
	search.savedHistory = nil;
end

local function FinishSearch()
	search.queue = nil;
	search.waitingSince = nil;
	RestoreSearchHistory();
	table.sort(results, function(x, y) return (x.minPrice or 0) < (y.minPrice or 0); end);
	UpdateResults();
	UpdateItemList();
end

local function SendNextQuery()
	local term = search.queue and table.remove(search.queue, 1);
	if not term then
		FinishSearch();
		return;
	end

	search.done = search.done + 1;
	search.waitingSince = GetTime();
	UpdateResults();

	C_AuctionHouse.SendBrowseQuery({
		searchString = term,
		filters = {},
		sorts = { { sortOrder = 0, reverseSort = false } },
	});
end

function StartSearch(terms)
	if search.queue or not terms or #terms == 0 then
		return;
	end

	results = {};
	search.queue = {};
	for _, term in ipairs(terms) do
		table.insert(search.queue, term);
	end
	search.total = #search.queue;
	search.done = 0;
	search.seen = {};

	if type(AH_SEARCH_HISTORY) == "table" then
		search.savedHistory = {};
		for index, text in ipairs(AH_SEARCH_HISTORY) do
			search.savedHistory[index] = text;
		end
	end

	FauxScrollFrame_SetOffset(resultsScroll, 0);
	UpdateItemList();
	SendNextQuery();
end

local function CollectBrowseResults()
	for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		local itemKey = result.itemKey;
		if itemKey and (result.minPrice or 0) > 0 and (result.totalQuantity or 0) > 0 then
			local key = itemKey.itemID..":"..(itemKey.itemSuffix or 0);
			if not search.seen[key] then
				search.seen[key] = true;
				table.insert(results, result);
			end
		end
	end
end

searchListButton:SetScript("OnClick", function()
	StartSearch(GetCurrentList().items);
end);

-----------------------------------------
-- События и вкладка
-----------------------------------------

frame:SetScript("OnShow", function()
	UpdateItemList();
	UpdateResults();
end);

frame:SetScript("OnUpdate", function()
	if search.queue and search.waitingSince and GetTime() - search.waitingSince > QUERY_TIMEOUT then
		SendNextQuery();
	end
end);

local watcher = CreateFrame("Frame");
watcher:SetScript("OnEvent", function(self, event)
	if event == "AUCTION_HOUSE_CLOSED" then
		if search.queue then
			FinishSearch();
		end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		if search.queue and search.waitingSince then
			search.waitingSince = nil;
			CollectBrowseResults();
			SendNextQuery();
		end
	elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
		if frame:IsVisible() then
			UpdateResults();
		end
	end
end);
watcher:RegisterEvent("AUCTION_HOUSE_CLOSED");
if watcher.RegisterCustomEvent then
	watcher:RegisterCustomEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");
	watcher:RegisterCustomEvent("ITEM_KEY_ITEM_INFO_RECEIVED");
end

local tabs = ahFrame.Tabs;
local tab = CreateFrame("Button", "AuctionHouseFrameAuctionatorShopTab", ahFrame, "AuctionHouseFrameDisplayModeTabTemplate");
tab:SetAttribute("displayMode", MODE);
tab:SetText(ZT("Shopping Lists"));
tab:SetPoint("LEFT", tabs[#tabs], "RIGHT", 2, 0);
table.insert(tabs, tab);
tab:SetID(#tabs);
PanelTemplates_SetNumTabs(ahFrame, #tabs);
if ahFrame.tabsForDisplayMode then
	ahFrame.tabsForDisplayMode[AuctionHouseFrameDisplayMode[MODE]] = #tabs;
end
PanelTemplates_TabResize(tab, 16);
PanelTemplates_DeselectTab(tab);

local origUpdateTitle = ahFrame.UpdateTitle;
ahFrame.UpdateTitle = function(self, ...)
	if origUpdateTitle then
		origUpdateTitle(self, ...);
	end

	if PanelTemplates_GetSelectedTab(self) == tab:GetID() then
		local title = ZT("Shopping Lists");
		if PortraitFrameTemplate_SetTitle then
			PortraitFrameTemplate_SetTitle(self, title);
		end
		if MetalFrame2X_SetTitle then
			MetalFrame2X_SetTitle(self, title);
		end
	end
end;
