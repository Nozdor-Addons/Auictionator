-- Аукцион NOZDOR.
--
-- На сервере NOZDOR окно аукциона заменено (Custom_AuctionHouseUI, API C_AuctionHouse):
-- стокового AuctionFrame нет и Blizzard_AuctionUI не загружается, поэтому вкладки
-- Auctionator не создаются. Цены для подсказок и API берутся из результатов нового окна:
-- обзора, списка товара и списка лотов предмета. В базу пишется минимальная цена за штуку.

local RETRY_INTERVAL = 1;
local RETRY_TIMEOUT = 30;

local watcher = CreateFrame("Frame");
local pending = {};
local noticeShown = false;

local function IsNozdorAuctionHouse()
	return C_AuctionHouse ~= nil and watcher.RegisterCustomEvent ~= nil;
end

local function ItemLink(itemID, itemSuffix)
	if itemSuffix and itemSuffix ~= 0 then
		return format("item:%d:0:0:0:0:0:%d", itemID, itemSuffix);
	end
	return "item:"..itemID;
end

-- false, если предмета ещё нет в кэше клиента: цену запишем, когда он появится.
local function StorePrice(link, unitPrice)
	local name, _, quality = GetItemInfo(link);
	if not name then
		return false;
	end

	if gAtr_ScanDB and quality + 1 >= (AUCTIONATOR_SCAN_MINLEVEL or 1) then
		gAtr_ScanDB[name] = unitPrice;
	end
	return true;
end

local function RecordPrice(itemID, itemSuffix, unitPrice)
	if not itemID or not unitPrice or unitPrice <= 0 then
		return;
	end

	local link = ItemLink(itemID, itemSuffix);
	if StorePrice(link, unitPrice) then
		pending[link] = nil;
	else
		pending[link] = { price = unitPrice, since = time() };
		watcher:Show();
	end
end

local function RecordBrowseResults(results)
	if not results then
		return;
	end

	for _, result in ipairs(results) do
		local itemKey = result.itemKey;
		if itemKey then
			RecordPrice(itemKey.itemID, itemKey.itemSuffix, result.minPrice);
		end
	end
end

local function RecordCommodityResults(itemID)
	if not itemID then
		return;
	end

	local lowest;
	for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0 do
		local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index);
		local unitPrice = info and info.unitPrice;
		if unitPrice and unitPrice > 0 and (not lowest or unitPrice < lowest) then
			lowest = unitPrice;
		end
	end

	RecordPrice(itemID, 0, lowest);
end

local function RecordItemResults(itemKey)
	if type(itemKey) ~= "table" or not itemKey.itemID then
		return;
	end

	local lowest;
	for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0 do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index);
		local quantity = info and info.quantity;
		local buyout = info and info.buyoutAmount;
		if buyout and quantity and quantity > 0 then
			local unitPrice = floor(buyout / quantity);
			if unitPrice > 0 and (not lowest or unitPrice < lowest) then
				lowest = unitPrice;
			end
		end
	end

	RecordPrice(itemKey.itemID, itemKey.itemSuffix, lowest);
end

watcher:SetScript("OnEvent", function(self, event, ...)
	if event == "AUCTION_HOUSE_SHOW" then
		if IsNozdorAuctionHouse() and not noticeShown then
			noticeShown = true;
			if DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage(ZT("Auctionator: prices are recorded while you browse the auction house. Auctionator tabs are not available in this auction window."), 0, 1, 1);
			end
		end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		RecordBrowseResults(C_AuctionHouse.GetBrowseResults());
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		RecordBrowseResults(...);
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
		RecordCommodityResults(...);
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
		RecordItemResults(...);
	end
end);

watcher.elapsed = 0;
watcher:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = self.elapsed + elapsed;
	if self.elapsed < RETRY_INTERVAL then
		return;
	end
	self.elapsed = 0;

	local now = time();
	local left = false;
	for link, entry in pairs(pending) do
		if StorePrice(link, entry.price) or now - entry.since > RETRY_TIMEOUT then
			pending[link] = nil;
		else
			left = true;
		end
	end

	if not left then
		self:Hide();
	end
end);
watcher:Hide();

watcher:RegisterEvent("AUCTION_HOUSE_SHOW");

if IsNozdorAuctionHouse() then
	watcher:RegisterCustomEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");
	watcher:RegisterCustomEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED");
	watcher:RegisterCustomEvent("COMMODITY_SEARCH_RESULTS_UPDATED");
	watcher:RegisterCustomEvent("COMMODITY_SEARCH_RESULTS_ADDED");
	watcher:RegisterCustomEvent("ITEM_SEARCH_RESULTS_UPDATED");
	watcher:RegisterCustomEvent("ITEM_SEARCH_RESULTS_ADDED");
end
