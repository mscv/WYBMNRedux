--[[
TO DO:
1) make use of newly available HousingLib.GetResidence() functionality:
	* info on harvest splits and nodes now available for neighbour plots on visit
	* info on repair state now available (both own and neighbour!
2) add garden plot functionality
3) test addon comms properly :)
--]]

require 'Apollo'
require 'GameLib'
require 'GuildLib'
require 'HousingPlot'
require 'HousingLib'
require 'ICCommLib'
require 'ICComm'
require 'XmlDoc'

local VERSION = '1.3.0'

local ONLINE_STALE_TIME = 30


local next, tsort, tremove, floor, max, getTime, rawset, strmatch, type = next, table.sort, table.remove, math.floor, math.max, os.time, rawset, string.match, type
local ICCommLib, XmlDoc, Apollo, GameLib, GuildLib, GetCurrentZoneName, HousingLib = ICCommLib, XmlDoc, Apollo, GameLib, GuildLib, GetCurrentZoneName, HousingLib
 
-----------------------------------------------------------------------------------------------
-- WYBMNRedux Module Definition
-----------------------------------------------------------------------------------------------
local Addon = Apollo.GetPackage('Gemini:Addon-1.1').tPackage:NewAddon('WYBMNRedux', true, { 'Gemini:DB-1.0', 'Gemini:Timer-1.0', 'Gemini:CallbackHandler-1.0', 'NeighborList' }, 'Gemini:Timer-1.0')
 
-----------------------------------------------------------------------------------------------
-- Vars
-----------------------------------------------------------------------------------------------

local tShares = {
	[0] = '100% to Owner',
	[1] = '75% to Owner',
	[2] = '50% to Owner',
	[3] = '25% to Owner',
	[4] = '0% to Owner'
}

local playerName = GameLib.GetAccountRealmCharacter().strCharacter

local tNodeType2Name = {
	[15] = HousingLib.GetPlugItem(517).strName,
	[25] = HousingLib.GetPlugItem(518).strName,
	[35] = HousingLib.GetPlugItem(520).strName,
	[11] = HousingLib.GetPlugItem(25).strName,
	[12] = HousingLib.GetPlugItem(26).strName,
	[13] = HousingLib.GetPlugItem(27).strName,
	[14] = HousingLib.GetPlugItem(44).strName,
	[21] = HousingLib.GetPlugItem(28).strName,
	[22] = HousingLib.GetPlugItem(30).strName,
	[23] = HousingLib.GetPlugItem(31).strName,
	[24] = HousingLib.GetPlugItem(46).strName,
	[31] = HousingLib.GetPlugItem(100).strName,
	[32] = HousingLib.GetPlugItem(121).strName,
	[33] = HousingLib.GetPlugItem(122).strName,
	[34] = HousingLib.GetPlugItem(123).strName,
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

local bAddonComms, bAutoToggle, bAutoAccept, bAutoDecline, bNoDeclineGuild

local wndMain, wndCurrentPlot, wndTargetPlot, wndCounter

local colorOnline = 'UI_TextHoloBodyHighlight'
local colorOffline = 'UI_BtnTextGrayNormal'

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
local tGuildMembers = {}
local tPlotInfos = {}
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------

function Addon:OnInitialize()
	Apollo.RegisterSlashCommand('wybmnr', 'OnSlashCmd', self)
	Apollo.RegisterSlashCommand('wybmnrvisit', 'OnButtonVisit', self)
	
	local defaults = {
		char = {
			myData = { name = playerName, faction = 0, privacyLevel = 4 },
			tNeighbourInfos = {},
			filterNodeType		= 1,
			filterNodeLevel		= 1,
			filterShareRatio	= 0,
			targetNeighbour		= 1,
		},
		profile = {
			bAddonComms			= true,
			bAutoToggle			= true,
			bAutoAccept			= false,
			bAutoDecline		= false,
			bNoDeclineGuild		= false,
		},
	}

	db = Apollo.GetPackage('Gemini:DB-1.0').tPackage:New(self, defaults, true)

	db.RegisterCallback(self, 'OnProfileChanged', 'DbProfileUpdate')
	db.RegisterCallback(self, 'OnProfileCopied', 'DbProfileUpdate')
	db.RegisterCallback(self, 'OnProfileReset', 'DbProfileUpdate')
	
	self.db = db
	-- needed for the search module
	self.tNodeType2Name = tNodeType2Name
	self.tShares = tShares
	self.tOnlineUsers = tOnlineUsers
end

function Addon:OnEnable()
	self.xmlDoc = XmlDoc.CreateFromFile('Core.xml')
	
	wndMain = Apollo.LoadForm(self.xmlDoc, 'WYBMNReduxMain', nil, self)
	wndCurrentPlot = wndMain:FindChild('plotInfo:currentPlot')
	wndTargetPlot = wndMain:FindChild('plotInfo:targetPlot')
	
	wndCounter = wndMain:FindChild('interfaceButtons:wndCounter')
	
	self.xmlDoc = nil
	
	wndMain:FindChild('headerInfo'):SetText('WYBMNRedux v'..VERSION)
	wndMain:Show(false, true)

	tNeighbourInfos = db.char.tNeighbourInfos
	
	self.myData = db.char.myData
	if self.myData.faction == 0 then
		self.myData.faction = GameLib.GetPlayerUnit():GetFaction()
	end
	
	self:DbProfileUpdate()
	
	if bAddonComms then
		self.channelOnlineInfo = ICCommLib.JoinChannel('WillYouBeMyNeighborOnlineChannel', ICCommLib.CodeEnumICCommChannelType.Global) -- we need this chan to listen at least to neighbours sending updates about their plots
		self.channelOnlineInfo:SetReceivedMessageFunction('OnMessageOnlineInfo', self)
		self:ScheduleRepeatingTimer('BroadcastOwnData', ONLINE_STALE_TIME)
	end

	Apollo.RegisterEventHandler('WindowManagementReady'      , 'OnWindowManagementReady'      , self)
	
	-- stuff here requires HousingLib to be fully loaded. There's no event for that, that I've found, so we keep trying ...
	self:DelayedEnable()
end

-----------------------------------------------------------------------------------------------
-- Functions
-----------------------------------------------------------------------------------------------

function Addon:DbProfileUpdate()
	bAddonComms		= db.profile.bAddonComms
	bAutoToggle		= db.profile.bAutoToggle
	bAutoAccept		= db.profile.bAutoAccept
	bAutoDecline	= db.profile.bAutoDecline
	bNoDeclineGuild	= db.profile.bNoDeclineGuild
end

local function removeNeighborListEventHandler()
	Apollo.RemoveEventHandler('HousingNeighborInviteRecieved', Apollo.GetAddon('NeighborList'))
end

function Addon:DelayedEnable()

	local bFullyLoaded = self:RefreshNeighbourList()
	
	if not bFullyLoaded then
		self:ScheduleTimer('DelayedEnable', 1)
		return
	end
	
	Apollo.RegisterEventHandler('ChangeWorld', 'OnChangeWorld', self)
	
	Apollo.RegisterEventHandler('HousingNeighborsLoaded', 'RefreshNeighbourList', self)
	Apollo.RegisterEventHandler('HousingNeighborInviteAccepted', 'OnHousingNeighborInviteAccepted', self)
	Apollo.RegisterEventHandler('HousingNeighborInviteDeclined', 'OnHousingNeighborInviteDeclined', self)

	Apollo.RegisterEventHandler('GuildRoster', 'OnGuildRoster', self)
	Apollo.RegisterEventHandler('GuildResult', 'OnGuildResult', self)
	
	Apollo.RegisterEventHandler('HousingNeighborInviteRecieved', 'OnNeighborInviteReceived', self)
	Apollo.RegisterEventHandler('HousingPlotsRecieved', 'OnPlotsReceived', self)
	
	for _, v in next, GuildLib.GetGuilds() do
		v:RequestMembers()
	end
	
	-- let's just hope NeighborList's OnDocumentReady fires by then ...
	self:ScheduleTimer(removeNeighborListEventHandler, 5)

	self:OnChangeWorld()
	self:OnPlotsReceived()
end

do
	local Event_FireGenericEvent = Event_FireGenericEvent
	function Addon:OnWindowManagementReady()
		Event_FireGenericEvent('WindowManagementAdd', { wnd = wndMain, strName = 'WYBMNRedux Main Window' })
	end
end

function Addon:OnPlotsReceived()
-- this event fires twice for some reason: the 1st time GetPlotCount() returns 0, the plots are NOT loaded, the 2nd time everything is in order
	if not HousingLib.IsHousingWorld() or HousingLib.GetResidence():GetPlotCount() == 0 then return end

	if HousingLib.IsOnMyResidence() then
		self:UpdateOwnData()
	end
	
	self:UpdateCurrentPlot()
	self:UpdateTargetPlot()

end
-- on SlashCommand '/wybmnr'
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
	
	local iRoomMates = 0
	for k, v in next, tNList do
		if not v.strCharacterName then 	-- on player login HousingLib takes a while to fully load and work properly - i.e. it returns the list of neighbours w/o providing their names ...
			return false
		end
		if v.ePermissionNeighbor == 2 then
			iRoomMates = iRoomMates + 1
		end
		if v.nId then
			local plotInfo = tNeighbourInfos[v.strCharacterName] or {}
			tNeighbours[k] = { name = v.strCharacterName, id = v.nId, lastOnline = v.fLastOnline, shareRatio = plotInfo.shareRatio, nodeType = plotInfo.nodeType  }
		end
	end
	tNeighbours[0] = { name = self.myData.name, id = 0, lastOnline = 0 , shareRatio = self.myData.shareRatio, nodeType = self.myData.nodeType } -- add self
	
	self.myData.bFull = #tNeighbours - iRoomMates >= 100
	
    self:UpdateTargetPlot()
	return true
end

do
	local String_GetWeaselString = String_GetWeaselString
	local function helperFDaysToTime(nDays)
		if nDays == nil then return	end
		if nDays == 0 then return Apollo.GetString('Neighbors_Online') end

		local tTimeInfo = {['name'] = '', ['count'] = nil}
		if nDays >= 30 then -- Months
			tTimeInfo.name = Apollo.GetString('CRB_Month')
			tTimeInfo.count = floor(nDays / 30)
		elseif nDays >= 1 then -- Days
			tTimeInfo.name = Apollo.GetString('CRB_Day')
			tTimeInfo.count = floor(nDays)
		else
			local nHours = nDays * 24
			if nHours >= 1 then -- Hours
				tTimeInfo.name = Apollo.GetString('CRB_Hour')
				tTimeInfo.count = floor(nHours)
			else -- Minutes
				tTimeInfo.name = Apollo.GetString('CRB_Min')
				tTimeInfo.count = max(floor(nHours%1*60),1)
			end
		end

		return String_GetWeaselString(Apollo.GetString('CRB_TimeOffline'), tTimeInfo)
	end

	function Addon:UpdateCurrentPlot()
		local currentResidence = HousingLib.GetResidence()
		local ownerName = currentResidence and currentResidence:GetPropertyOwnerName() or 'Unknown'
		
		local tOwnerData = tNeighbours[tNeighboursKeys[ownerName]] or { name = ownerName }
		
		wndCurrentPlot:FindChild('plotName'):SetText(tOwnerData.name or 'Unknown')
		wndCurrentPlot:FindChild('plotRatio'):SetText(tShares[tOwnerData.shareRatio] or 'Unknown')
		wndCurrentPlot:FindChild('plotType'):SetText(tNodeType2Name[tOwnerData.nodeType] or 'Unknown')
		wndCurrentPlot:FindChild('plotLastOnline'):SetText(helperFDaysToTime(tOwnerData.lastOnline) or 'Unknown')
		wndCurrentPlot:FindChild('plotName'):SetTextColor(tOwnerData.lastOnline == 0 and colorOnline or colorOffline)
	end

	function Addon:UpdateTargetPlot()
		local tOwnerData = tNeighbours[db.char.targetNeighbour] or {}
		
		wndTargetPlot:FindChild('plotName'):SetText(tOwnerData.name or 'Unknown')
		wndTargetPlot:FindChild('plotRatio'):SetText(tShares[tOwnerData.shareRatio] or 'Unknown')
		wndTargetPlot:FindChild('plotType'):SetText(tNodeType2Name[tOwnerData.nodeType] or 'Unknown')
		wndTargetPlot:FindChild('plotLastOnline'):SetText(helperFDaysToTime(tOwnerData.lastOnline) or 'Unknown')
		wndTargetPlot:FindChild('plotName'):SetTextColor(tOwnerData.lastOnline == 0 and colorOnline or colorOffline)
		
		wndCounter:SetText(db.char.targetNeighbour .. '/' .. #tNeighbours)
	end
end

function Addon:OnChangeWorld()
	if not bAutoToggle then return end

	if HousingLib.IsHousingWorld() then
		wndMain:Invoke()
	else
		wndMain:Close()
	end
end

function Addon:UpdateOwnData()
	local currentResidence = HousingLib.GetResidence()
	if not currentResidence then return end
	
	local nodeType
	for i=1, currentResidence:GetPlotCount() do
		nodeType = tPlugItem2NodeType[HousingLib.GetPlot(i):GetPlugItemId() or 0]
		if nodeType then break	end
	end
	self.myData.nodeType = nodeType
	self.myData.shareRatio = currentResidence:GetNeighborHarvestSplit()
	self.myData.privacyLevel = currentResidence:GetResidencePrivacyLevel()
	
	tNeighbours[0] = { name = self.myData.name, id = 0, lastOnline = 0 , shareRatio = self.myData.shareRatio, nodeType = self.myData.nodeType } -- update self
end

function Addon:BroadcastOwnData()
	if not self.myData.nodeType or self.myData.privacyLevel > 1 then return end -- if nodeType doesn't exist, it means we don't have our data in the db or we have no harvest nodes at all; privacyLevel > 1 means roommates or better => nothing to broadcast
	self.channelOnlineInfo:SendMessage(self:Serialize(self.myData))
end

function Addon:NeighbourNext()
	return db.char.targetNeighbour >= #tNeighbours and 0 or db.char.targetNeighbour + 1
end

function Addon:NeighbourPrev()
	return db.char.targetNeighbour == 0 and #tNeighbours or db.char.targetNeighbour - 1
end

function Addon:OnMessageOnlineInfo(_, tMsg)
	tMsg = self:Deserialize(tMsg)
	if not tMsg.name or not tMsg.nodeType or not tMsg.shareRatio or not tMsg.faction or tMsg.faction ~= self.myData.faction then return end
	
	local nId = tNeighboursKeys[tMsg.name]
	if nId then
		tNeighbours[nId].shareRatio = tMsg.shareRatio
		tNeighbours[nId].nodeType	= tMsg.nodeType
		tNeighbourInfos[tMsg.name]	= tMsg
	elseif not tMsg.bFull then
		tMsg.lastSeen = getTime()
		tOnlineUsers[tMsg.name] = tMsg
	end
end

function Addon:NeighbourAdd(strName)
	if not strName then return end
	self:Print('Sending neighbour invite to: '..strName)
	HousingLib.NeighborInviteByName(strName)
end

function Addon:NeighbourRemove(iNeighbour)
	if not iNeighbour then return end

	if iNeighbour == 0 then
		self:Print('Can\'t remove yourself.')
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
		self:Print(strName.. ' accepted Your neighbour invite.')
	end
	self:ScheduleTimer('RefreshNeighbourList', 3) -- it needs to be delayed, since HousingLib doesn't get an update immediately and NeighborsLoaded fires only after REMOVAL of a neigbour ...
end

function Addon:OnHousingNeighborInviteDeclined(strName)
	if not strName or strName == '' then return end -- empty when it's us that have declined an invite
	self:Print(strName.. ' declined Your neighbour invite.')
end

function Addon:GetOnlineUsersFiltered()
	local tFiltered = {}

	local filterNodeType = db.char.filterNodeType
	local filterNodeLevel = db.char.filterNodeLevel
	local filterShareRatio = db.char.filterShareRatio
	
	local staleTimeNew = getTime() - ONLINE_STALE_TIME

	for k,v in next, tOnlineUsers do
		if v.lastSeen < staleTimeNew or tNeighboursKeys[k]  then -- purge old data & people we have just added to neighbours
			tOnlineUsers[k] = nil
		elseif floor(v.nodeType / 10) == filterNodeType and v.nodeType%10 >= filterNodeLevel and v.shareRatio >= filterShareRatio then
			tFiltered[k] = v
		end
	end
	
	return tFiltered
end

function Addon:OnNeighborInviteReceived(strName)
	if bAutoDecline and ( not bNoDeclineGuild or not tGuildMembers[strName] ) then
		local tOnlineUsersFiltered = self:GetOnlineUsersFiltered()
		if not tOnlineUsersFiltered[strName] then
			HousingLib.NeighborInviteDecline()
			self:Print('Neighbour invite from '..strName.. ' declined based on filters.')
			return
		end
	end
	if bAutoAccept then
		HousingLib.NeighborInviteAccept()
		self:Print('Neighbour invite from '..strName.. ' accepted.')
		return
	end

	Apollo.GetAddon('NeighborList'):OnNeighborInviteRecieved(strName)
end

function Addon:OnGuildRoster(_, tRoster )
	for _, v in next, tRoster do
		tGuildMembers[v.strName] = true
	end
end

function Addon:OnGuildResult(_, strName, _, eResult )
	if eResult == GuildLib.GuildResult_KickedMember or eResult == GuildLib.GuildResult_MemberQuit then
		tGuildMembers[strName] = nil
	end
	
	if eResult == GuildLib.GuildResult_InviteAccepted then
		tGuildMembers[strName] = true
	end
end

do
	local Print = Print
	function Addon:Print(strMsg)
		Print('WYBMNRedux: ' .. strMsg)
	end
end

function Addon:Serialize(t)
	local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
	local type = type(t)
	if type == "string" then
		return ("%q"):format(t)
	elseif type == "table" then
		local tbl = {"{"}
		local indexed = #t > 0
		local hasValues = false
		for k, v in pairs(t) do
			hasValues = true
			tinsert(tbl, indexed and self:Serialize(v) or "[" .. self:Serialize(k) .. "]=" .. self:Serialize(v))
			tinsert(tbl, ",")
		end
		if hasValues then
			tremove(tbl, #tbl)
		end
		tinsert(tbl, "}")
		return tconcat(tbl)
	end
	return tostring(t)
end

function Addon:Deserialize(str)
	local func = loadstring("return {" .. str .. "}")
	if func then
		setfenv(func, {})
		local succeeded, ret = pcall(func)
		if succeeded then
			return unpack(ret)
		end
	end
	return {}
end

-----------------------------------------------------------------------------------------------
-- Form Functions
-----------------------------------------------------------------------------------------------

function Addon:OnButtonClose()
	wndMain:Close() -- hide the window
end

function Addon:OnButtonVisit()
	if not HousingLib.IsHousingWorld() then
		self:Print('Cannot do that outside the housing system.')
		return
	end
	
	if db.char.targetNeighbour == 0 then
		HousingLib.RequestTakeMeHome()
	else
		HousingLib.VisitNeighborResidence( tNeighbours[db.char.targetNeighbour].id )
	end
	db.char.targetNeighbour = self:NeighbourNext()
end

function Addon:OnButtonPrev()
	db.char.targetNeighbour = self:NeighbourPrev()
	self:UpdateTargetPlot()
end

function Addon:OnButtonNext()
	db.char.targetNeighbour = self:NeighbourNext()
	self:UpdateTargetPlot()
end

function Addon:OnButtonHome()
	if not HousingLib.IsHousingWorld() then
		self:Print('Cannot do that outside the housing system.')
		return
	end
	HousingLib.RequestTakeMeHome()
end

function Addon:OnButtonDelete()
	self:NeighbourRemove( db.char.targetNeighbour )
	self:UpdateTargetPlot()
end

function Addon:OnConfigure()
	self:GetModule('Settings'):Toggle()
end

function Addon:OnSearch()
	self:GetModule('Search'):Toggle()
end
