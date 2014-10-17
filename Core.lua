--[[

TO DO:
1) convert tNeighbours into a circular DLL
2) decouple target neighbour from current neighbour
--]]

local VERSION = '1.0.3'
local FAKE_WYBMN_VERSION = 1.047

local ONLINE_STALE_TIME
local ONLINE_STALE_TIME_NEW = 30
local ONLINE_STALE_TIME_LEGACY = 10 -- the original WYBMN ignores users not seen in the past 10s


local next, tsort, tremove, floor, max, getTime = next, table.sort, table.remove, math.floor, math.max, os.time
local ICCommLib, XmlDoc, Apollo, ApolloColor, GameLib, HousingLib, String_GetWeaselString = ICCommLib, XmlDoc, Apollo, ApolloColor, GameLib, HousingLib, String_GetWeaselString
 
-----------------------------------------------------------------------------------------------
-- WYBMNRedux Module Definition
-----------------------------------------------------------------------------------------------
local Addon = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("WYBMNRedux", true, { 'Gemini:DB-1.0', 'Gemini:Timer-1.0', 'Gemini:CallbackHandler-1.0', 'NeighborList' }, 'Gemini:Timer-1.0')
 
-----------------------------------------------------------------------------------------------
-- Vars
-----------------------------------------------------------------------------------------------

local tShares = {
	[0] = "100% to Owner",
	[1] = "75% to Owner",
	[2] = "50% to Owner",
	[3] = "25% to Owner",
	[4] = "0% to Owner"
}

local playerName = GameLib.GetAccountRealmCharacter().strCharacter

local tNodeType2Name = {
	[15] = HousingLib.GetPlugItem(517)[1].strName,
	[25] = HousingLib.GetPlugItem(518)[1].strName,
	[35] = HousingLib.GetPlugItem(520)[1].strName,
	[11] = HousingLib.GetPlugItem(25)[1].strName,
	[12] = HousingLib.GetPlugItem(26)[1].strName,
	[13] = HousingLib.GetPlugItem(27)[1].strName,
	[14] = HousingLib.GetPlugItem(44)[1].strName,
	[21] = HousingLib.GetPlugItem(28)[1].strName,
	[22] = HousingLib.GetPlugItem(30)[1].strName,
	[23] = HousingLib.GetPlugItem(31)[1].strName,
	[24] = HousingLib.GetPlugItem(46)[1].strName,
	[31] = HousingLib.GetPlugItem(100)[1].strName,
	[32] = HousingLib.GetPlugItem(121)[1].strName,
	[33] = HousingLib.GetPlugItem(122)[1].strName,
	[34] = HousingLib.GetPlugItem(123)[1].strName,
}

local tPlugItem2NodeType = {
	[517] = 15,
	[518] = 25,
	[520] = 35,
	 [25] = 11,
	 [26] = 12,
	 [27] = 13,
	 [44] = 14,
	 [28] = 21,
	 [30] = 22,
	 [31] = 23,
	 [46] = 24,
	[100] = 31,
	[121] = 32,
	[122] = 33,
	[123] = 34,
}

local bAddonComms, bLegacySupport, bAutoToggle, bAutoAccept, bAutoDecline

local wndMain, wndCurrentPlot, wndTargetPlot, wndCounter

local colorOnline = ApolloColor.new("UI_TextHoloBodyHighlight")
local colorOffline = ApolloColor.new("UI_BtnTextGrayNormal")

local db

local tNeighboursKeys = {}
local tNeighbours = setmetatable({}, {__newindex =
	function(self, key, value)
		tNeighboursKeys[value.name] = key
		rawset(self, key, value)
	end,
})

local tOnlineUsers = {}
local tNeighbourInfos = {}

local tPlotInfos = {}
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------

function Addon:OnInitialize()
	Apollo.RegisterSlashCommand("wybmnr", "OnSlashCmd", self)
	Apollo.RegisterSlashCommand("wybmnrvisit", "OnButtonVisit", self)
	
	local defaults = {
		char = {
			myData = { name = playerName, faction = 0 },
			myDataLegacy = { name = playerName, activity = 0, month = 0, remaining = 0, version = FAKE_WYBMN_VERSION, faction = 0 },
			tNeighbourInfos = {},
			filterNodeType		= 1,
			filterNodeLevel		= 1,
			filterShareRatio	= 0,
		},
		profile = {
			bAddonComms			= true,
			bLegacySupport		= true,
			bAutoToggle			= true,
			bAutoAccept			= false,
			bAutoDecline		= false,
		},
	}

	db = Apollo.GetPackage("Gemini:DB-1.0").tPackage:New(self, defaults, true)

	db.RegisterCallback(self, "OnProfileChanged", 'DbProfileUpdate')
	db.RegisterCallback(self, "OnProfileCopied", 'DbProfileUpdate')
	db.RegisterCallback(self, "OnProfileReset", 'DbProfileUpdate')
	
	self.db = db
	-- needed for the search module
	self.tNodeType2Name = tNodeType2Name
	self.tShares = tShares
	self.tOnlineUsers = tOnlineUsers
end

function Addon:OnEnable()
	self.xmlDoc = XmlDoc.CreateFromFile("Core.xml")
	
	wndMain = Apollo.LoadForm(self.xmlDoc, "WYBMNReduxMain", nil, self)
	wndCurrentPlot = wndMain:FindChild('plotInfo:currentPlot')
	wndTargetPlot = wndMain:FindChild('plotInfo:targetPlot')
	
	wndCounter = wndMain:FindChild('interfaceButtons:wndCounter')
	
	self.xmlDoc = nil
	
	wndMain:FindChild('headerInfo'):SetText('WYBMN Redux v'..VERSION)
	wndMain:Show(false, true)

	self.currentNeighbour = 0
	
	tNeighbourInfos = db.char.tNeighbourInfos
	
	self.myData = db.char.myData
	self.myDataLegacy = db.char.myDataLegacy
	if self.myData.faction == 0 then
		self.myData.faction = GameLib.GetPlayerUnit():GetFaction()
		self.myDataLegacy.faction = self.myData.faction
	end
	
	self:DbProfileUpdate()
	
	ONLINE_STALE_TIME = bLegacySupport and ONLINE_STALE_TIME_LEGACY or ONLINE_STALE_TIME_NEW

	if bAddonComms then
		if bLegacySupport then -- listen to legacy plot info messages
			self.channelPlotInfos = ICCommLib.JoinChannel("WillYouBeMyNeighborChannel", "OnMessagePlotInfo", self)
		end
		self.channelOnlineInfo = ICCommLib.JoinChannel("WillYouBeMyNeighborOnlineChannel", "OnMessageOnlineInfo", self) -- we need this chan to listen at least to neighbours sending updates about their plots
		self:ScheduleRepeatingTimer('BroadcastOwnData', ONLINE_STALE_TIME)
	end

	-- stuff here requires HousingLib to be fully loaded. There's no event for that, that I've found, so we keep trying ...
	self:DelayedEnable()
end

-----------------------------------------------------------------------------------------------
-- Functions
-----------------------------------------------------------------------------------------------

local function helperFDaysToTime(nDays)
	if nDays == nil then return	end
	if nDays == 0 then return Apollo.GetString("Neighbors_Online") end

	local tTimeInfo = {["name"] = "", ["count"] = nil}
	if nDays >= 30 then -- Months
		tTimeInfo.name = Apollo.GetString("CRB_Month")
		tTimeInfo.count = floor(nDays / 30)
	elseif nDays >= 1 then -- Days
		tTimeInfo.name = Apollo.GetString("CRB_Day")
		tTimeInfo.count = floor(nDays)
	else
		local nHours = nDays * 24
		if nHours >= 1 then -- Hours
			tTimeInfo.name = Apollo.GetString("CRB_Hour")
			tTimeInfo.count = floor(nHours)
		else -- Minutes
			tTimeInfo.name = Apollo.GetString("CRB_Min")
			tTimeInfo.count = max(floor(nHours%1*60),1)
		end
	end

	return String_GetWeaselString(Apollo.GetString("CRB_TimeOffline"), tTimeInfo)
end

function Addon:DbProfileUpdate()
	bAddonComms		= db.profile.bAddonComms
	bLegacySupport	= db.profile.bLegacySupport
	bAutoToggle		= db.profile.bAutoToggle
	bAutoAccept		= db.profile.bAutoAccept
	bAutoDecline	= db.profile.bAutoDecline
end

local function removeNeighborListEventHandler()
	Apollo.RemoveEventHandler("HousingNeighborInviteRecieved", Apollo.GetAddon("NeighborList"))
end

function Addon:DelayedEnable()

	local bFullyLoaded = self:RefreshNeighbourList()
	
	if not bFullyLoaded then
		self:ScheduleTimer('DelayedEnable', 1)
		return
	end
	
	Apollo.RegisterEventHandler("ChangeWorld", "OnChangeWorld", self)
	Apollo.RegisterEventHandler("HousingNeighborsLoaded", "RefreshNeighbourList", self)
	Apollo.RegisterEventHandler('HousingNeighborInviteAccepted', 'OnHousingNeighborInviteAccepted', self)
	Apollo.RegisterEventHandler('HousingNeighborInviteDeclined', 'OnHousingNeighborInviteDeclined', self)
	Apollo.RegisterEventHandler("HousingNeighborInviteRecieved", 	"OnNeighborInviteReceived", self)
	
	-- let's just hope NeighborList's OnDocumentReady fires by then ...
	self:ScheduleTimer(removeNeighborListEventHandler, 5)

	self:OnChangeWorld()
end

-- on SlashCommand "/wybmnr"
function Addon:OnSlashCmd()
	wndMain:Invoke() -- show the window
	
	self:UpdateCurrentPlot()
    self:UpdateTargetPlot()
end

local function sortNB(a, b)
	if a.ePermissionNeighbor ~= b.ePermissionNeighbor then
		return a.ePermissionNeighbor > b.ePermissionNeighbor
	else
		return ( a.strCharacterName or '' ) < ( b.strCharacterName or '' )
	end
end

function Addon:RefreshNeighbourList()
	local tNList = HousingLib.GetNeighborList()
	tsort(tNList, sortNB)
	
	while tremove(tNeighbours) do end
	while tremove(tNeighboursKeys) do end
	
	for k, v in next, tNList do
		if not v.strCharacterName then 	-- on player login HousingLib takes a while to fully load and work properly - i.e. it returns the list of neighbours w/o providing their names ...
			return false
		end

		local plotInfo = tNeighbourInfos[v.strCharacterName] or {}
		tNeighbours[k] = { name = v.strCharacterName, id = v.nId, lastOnline = v.fLastOnline, shareRatio = plotInfo.shareRatio, nodeType = plotInfo.nodeType  }
	end
	tNeighbours[0] = { name = self.myData.name, id = 0, lastOnline = 0 , shareRatio = self.myData.shareRatio, nodeType = self.myData.nodeType } -- add self
	
    self:UpdateTargetPlot()
	
	return true
end

function Addon:UpdateCurrentPlot()
	local ownerName
	if HousingLib:IsHousingWorld() and not HousingLib:IsWarplotResidence() then
		ownerName = HousingLib:IsOnMyResidence() and playerName or string.match(GetCurrentZoneName() or 'UNKNOWN', "%[([^%]]+)%]")
		if not ownerName then
			self:ScheduleTimer('OnChangeWorld', 0.5)
			return
		end
		self.currentNeighbour = tNeighboursKeys[ownerName] or self.currentNeighbour
	end
	
	local tOwnerData = tNeighbours[self.currentNeighbour] or { name = ownerName }
	
	wndCurrentPlot:FindChild("plotName"):SetText(tOwnerData.name or 'Unknown')
	wndCurrentPlot:FindChild("plotRatio"):SetText(tShares[tOwnerData.shareRatio] or 'Unknown')
	wndCurrentPlot:FindChild("plotType"):SetText(tNodeType2Name[tOwnerData.nodeType] or 'Unknown')
	wndCurrentPlot:FindChild("plotLastOnline"):SetText(helperFDaysToTime(tOwnerData.lastOnline) or 'Unknown')
	wndCurrentPlot:FindChild("plotName"):SetTextColor(tOwnerData.lastOnline == 0 and colorOnline or colorOffline)
end

function Addon:UpdateTargetPlot()
	local tOwnerData = tNeighbours[self:NeighbourNext()] or {}
	
	wndTargetPlot:FindChild("plotName"):SetText(tOwnerData.name or 'Unknown')
	wndTargetPlot:FindChild("plotRatio"):SetText(tShares[tOwnerData.shareRatio] or 'Unknown')
	wndTargetPlot:FindChild("plotType"):SetText(tNodeType2Name[tOwnerData.nodeType] or 'Unknown')
	wndTargetPlot:FindChild("plotLastOnline"):SetText(helperFDaysToTime(tOwnerData.lastOnline) or 'Unknown')
	wndTargetPlot:FindChild("plotName"):SetTextColor(tOwnerData.lastOnline == 0 and colorOnline or colorOffline)
	
	wndCounter:SetText(self:NeighbourNext() .. '/' .. #tNeighbours)
end

function Addon:OnChangeWorld()
	if bAutoToggle then
		if not HousingLib:IsHousingWorld() then 
			if wndMain:IsShown() then wndMain:Close() return end
		else
			if not wndMain:IsShown() then wndMain:Invoke() end
		end
	end
	
	if HousingLib:IsHousingWorld() and HousingLib:IsOnMyResidence() and not HousingLib:IsWarplotResidence() then
		self:UpdateOwnData()
	end
	
	self:UpdateCurrentPlot()
    self:UpdateTargetPlot()
end

function Addon:UpdateOwnData()
	local nodeType
	for i=1,7 do
		nodeType = tPlugItem2NodeType[HousingLib.GetPlot(i).nPlugItemId]
		if nodeType then break	end
	end
	self.myData.nodeType = nodeType
	self.myData.shareRatio = HousingLib.GetNeighborHarvestSplit()
	if bLegacySupport then
		self.myDataLegacy.share		= self.myData.shareRatio
		self.myDataLegacy.nodetype	= tNodeType2Name[self.myData.nodeType]
		self.myDataLegacy.timestamp	= getTime() + 100000 -- doesn't matter
	end
	
	tNeighbours[0] = { name = self.myData.name, id = 0, lastOnline = 0 , shareRatio = self.myData.shareRatio, nodeType = self.myData.nodeType } -- update self

end

function Addon:BroadcastOwnData()
	if not self.myData.nodeType then return end -- if this key doesn't exist, it means we don't have our data in the db or we have no harvest nodes at all => nothing to broadcast
	self.channelOnlineInfo:SendMessage(self.myData)
	if bLegacySupport then
		self.channelPlotInfos:SendMessage(self.myDataLegacy)
	end
end

function Addon:NeighbourNext()
	return self.currentNeighbour == #tNeighbours and 0 or self.currentNeighbour + 1
end

function Addon:NeighbourPrev()
	return self.currentNeighbour == 0 and #tNeighbours or self.currentNeighbour - 1
end

function Addon:OnMessageOnlineInfo(_, tMsg)
	if not tMsg.nodeType and bLegacySupport and tMsg.name then -- fill in data from tPlotInfos, as this is a legacy message
		local plotInfo = tPlotInfos[tMsg.name]
		if not plotInfo then return end  -- just wait for the next message, the sender spams both types
		
		tMsg.nodeType	= plotInfo.nodeType
		tMsg.shareRatio	= plotInfo.shareRatio
		tMsg.faction	= plotInfo.faction
		
		tMsg.legacy		= true
	end
	
	if not tMsg.name or not tMsg.nodeType or not tMsg.shareRatio or not tMsg.faction or tMsg.faction ~= self.myData.faction then return end
	
	tMsg.lastSeen = getTime()
	
	local nId = tNeighboursKeys[tMsg.name]
	if nId then
		tNeighbours[nId].shareRatio = tMsg.shareRatio
		tNeighbours[nId].nodeType	= tMsg.nodeType
		tNeighbourInfos[tMsg.name]	= tMsg
	else
		tOnlineUsers[tMsg.name] = tMsg
	end
end


--XXX required only for legacy WYBMN support
do
	local tNodeName2Type = {
		-- enUS
		["Mineral Deposit Tier 1"]		= 11,
		["Mineral Deposit Tier 2"]		= 12,
		["Mineral Deposit Tier 3"]		= 13,
		["Mineral Deposit Tier 4"]		= 14,
		["Elite Mineral Deposit"]		= 15,
		["Relic Excavation Tier 1"]		= 21,
		["Relic Excavation Tier 2"]		= 22,
		["Relic Excavation Tier 3"]		= 23,
		["Relic Excavation Tier 4"]		= 24,
		["Elite Relic Excavation"]		= 25,
		["Thicket Tier 1"]				= 31,
		["Thicket Tier 2"]				= 32,
		["Thicket Tier 3"]				= 33,
		["Thicket Tier 4"]				= 34,
		["Elite Thicket"]				= 35,

		-- deDe
		["Mineralvorkommen (Rang 1)"]	= 11,
		["Mineralvorkommen (Rang 2)"]	= 12,
		["Mineralvorkommen (Rang 3)"]	= 13,
		["Mineralvorkommen (Rang 4)"]	= 14,
		["Elite-Mineralvorkommen"]		= 15,
		["Reliktausgrabung (Rang 1)"]	= 21,
		["Reliktausgrabung (Rang 2)"]	= 22,
		["Reliktausgrabung (Rang 3)"]	= 23,
		["Reliktausgrabung (Rang 4)"]	= 24,
		["Elite-Reliktausgrabung"]		= 25,
		["Dickicht (Rang 1)"]			= 31,
		["Dickicht (Rang 2)"]			= 32,
		["Dickicht (Rang 3)"]			= 33,
		["Dickicht (Rang 4)"]			= 34,
		["Elite-Dickicht"]				= 35,
	}
	function Addon:OnMessagePlotInfo(_, tMsg)
		if type(tMsg) ~= 'table' then return end
		
		if not tMsg.name or not tMsg.share or not tMsg.nodetype or not tMsg.faction or not tMsg.remaining or not tMsg.timestamp or not tMsg.version or type(tMsg.share) == 'table' then return end

		if tMsg.faction ~= self.myData.faction then return end -- not sure if addon comms are xfaction

		if not tNodeName2Type[tMsg.nodetype] then return end -- no nodes or not supported lang
		
		if tPlotInfos[tMsg.name] and tPlotInfos[tMsg.name].timeStamp >= tMsg.timestamp then return end -- old data received

		-- update tPlotInfos to supplement online messages
		local plotInfo = {
			timeStamp	= tMsg.timestamp,
			shareRatio	= tMsg.share,
			nodeType	= tNodeName2Type[tMsg.nodetype],
			faction		= tMsg.faction,
		}
		tPlotInfos[tMsg.name] = plotInfo
		
		-- update tNeighbours and tNeighbourInfos, doing this here as well to make use of "replay" messages (i.e. plot information not comming from the owner)
		local nId = tNeighboursKeys[tMsg.name]
		if nId then
			tNeighbours[nId].shareRatio = plotInfo.shareRatio
			tNeighbours[nId].nodeType	= plotInfo.nodeType
			tNeighbourInfos[tMsg.name]	= plotInfo
		end
	end
end

function Addon:NeighbourAdd(strName)
	if not strName then return end
	Print('WYBMNRedux: Sending neighbour invite to: '..strName)
	HousingLib.NeighborInviteByName(strName)
end

function Addon:NeighbourRemove(iNeighbour)
	if not iNeighbour then return end

	if iNeighbour == 0 then
		Print("Can't remove yourself.")
		return
	end
	
	local neighbour = tNeighbours[iNeighbour]
	if not neighbour then return end

	HousingLib.NeighborEvict(neighbour.id)
	tremove(tNeighbours, iNeighbour)
	tNeighboursKeys[neighbour.name] = nil
	tNeighbourInfos[neighbour.name] = nil
end

function Addon:OnHousingNeighborInviteAccepted(strName)
	if strName and strName ~= '' then -- empty when it's us that have accepted an invite
		Print('WYBMNRedux: '..strName.. ' accepted Your neighbour invite.')
	end
	self:ScheduleTimer('RefreshNeighbourList', 3) -- it needs to be delayed, since HousingLib doesn't get an update immediately and NeighborsLoaded fires only after REMOVAL of a neigbour ...
end

function Addon:OnHousingNeighborInviteDeclined(strName)
	if not strName or strName == '' then return end -- empty when it's us that have declined an invite
	Print('WYBMNRedux: '..strName.. ' declined Your neighbour invite.')
end

function Addon:GetOnlineUsersFiltered()
	local tFiltered = {}

	local filterNodeType = db.char.filterNodeType
	local filterNodeLevel = db.char.filterNodeLevel
	local filterShareRatio = db.char.filterShareRatio
	
	local staleTimeNew = getTime() - ONLINE_STALE_TIME_NEW
	local staleTimeLegacy = getTime() - ONLINE_STALE_TIME_LEGACY

	for k,v in next, tOnlineUsers do
		if v.lastSeen < (v.legacy and staleTimeLegacy or staleTimeNew)  then
			tOnlineUsers[k] = nil
		elseif floor(v.nodeType / 10) == filterNodeType and v.nodeType%10 >= filterNodeLevel and v.shareRatio >= filterShareRatio then
			tFiltered[k] = v
		end
	end
	
	return tFiltered
end

function Addon:OnNeighborInviteReceived(strName)
	if bAutoDecline then
		local tOnlineUsersFiltered = self:GetOnlineUsersFiltered()
		if not tOnlineUsersFiltered[strName] then
			HousingLib.NeighborInviteDecline()
			Print('WYBMNRedux: Neighbour invite from '..strName.. ' declined based on filters.')
			return
		end
	end
	if bAutoAccept then
		HousingLib.NeighborInviteAccept()
		Print('WYBMNRedux: Neighbour invite from '..strName.. ' accepted.')
		return
	end

	Apollo.GetAddon("NeighborList"):OnNeighborInviteRecieved(strName)
end

-----------------------------------------------------------------------------------------------
-- Form Functions
-----------------------------------------------------------------------------------------------

function Addon:OnButtonClose()
	wndMain:Close() -- hide the window
end

function Addon:OnButtonVisit()
    if not HousingLib.IsHousingWorld() then return end
	
	if self:NeighbourNext() == 0 then
		HousingLib.RequestTakeMeHome()
	else
		HousingLib.VisitNeighborResidence( tNeighbours[self:NeighbourNext()].id )
	end
end

function Addon:OnButtonPrev()
	self.currentNeighbour = self:NeighbourPrev()
	self:UpdateTargetPlot()
end

function Addon:OnButtonNext()
	self.currentNeighbour = self:NeighbourNext()
	self:UpdateTargetPlot()
end

function Addon:OnButtonHome()
	if not HousingLib:IsHousingWorld() then
		Print('WYBMNRedux: Cannot do that outside the housing system.')
		return
	end
	HousingLib.RequestTakeMeHome()
end

function Addon:OnButtonDelete()
	self:NeighbourRemove( self:NeighbourNext() )
	self:UpdateTargetPlot()
end

function Addon:OnConfigure()
	self:GetModule("Settings"):Toggle()
end

function Addon:OnSearch()
	self:GetModule("Search"):Toggle()
end
