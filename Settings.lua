
local Apollo, XmlDoc, HousingLib = Apollo, XmlDoc, HousingLib

local core = Apollo.GetAddon('WYBMNRedux')
local module = core:NewModule('Settings')

local wndSettings
local addonHousingRemodel

local function dbProfileUpdate()
	wndSettings:FindChild('btnAutoToggle'):SetCheck(core.db.profile.bAutoToggle)
	wndSettings:FindChild('btnAddonComms'):SetCheck(core.db.profile.bAddonComms)
	wndSettings:FindChild('btnLegacySupport'):SetCheck(core.db.profile.bLegacySupport)
	wndSettings:FindChild('btnAutoAccept'):SetCheck(core.db.profile.bAutoAccept)
	wndSettings:FindChild('btnAutoDecline'):SetCheck(core.db.profile.bAutoDecline)
	wndSettings:FindChild('btnNoDeclineGuild'):SetCheck(core.db.profile.bNoDeclineGuild)
end

function module:OnInitialize()
	self.xmlDoc = XmlDoc.CreateFromFile('Settings.xml')
	
	core.db.RegisterCallback(self.Name, 'OnProfileReset', dbProfileUpdate)
	core.db.RegisterCallback(self.Name, 'OnProfileChanged', dbProfileUpdate)
	core.db.RegisterCallback(self.Name, 'OnProfileCopied', dbProfileUpdate)
	
	Apollo.RegisterEventHandler('ObscuredAddonVisible', '__OnHousingRemodelVisible', self)
end

function module:OnEnable()
	wndSettings = Apollo.LoadForm(self.xmlDoc, 'WYBMNReduxSettings', nil, self)
	wndSettings:Show(false)

	dbProfileUpdate()
	
	self:__OnHousingRemodelVisible('HousingRemodel')
end

function module:__OnHousingRemodelVisible(strAddonName)
	if strAddonName ~= 'HousingRemodel' then return end
	
	addonHousingRemodel = Apollo.GetAddon('HousingRemodel')

	if addonHousingRemodel == nil then return end
	
	local fnOldHousingRemodelOnSettingsCancel = addonHousingRemodel.OnSettingsCancel
	addonHousingRemodel.OnSettingsCancel = function ( self, wndHandler, wndControl, eMouseButton )
		fnOldHousingRemodelOnSettingsCancel( self, wndHandler, wndControl, eMouseButton )
		core:UpdateOwnData()
		core:UpdateCurrentPlot()
	end
	self.__OnHousingRemodelVisible = nil
	Apollo.RemoveEventHandler('ObscuredAddonVisible', self)
end

-----------------------------------------------------------------------------------------------
-- Form Functions
-----------------------------------------------------------------------------------------------

function module:OnBtnAutoToggle(wndHandler, wndControl)
	core.db.profile.bAutoToggle = wndControl:IsChecked()
	core:DbProfileUpdate() -- needed to refresh upvalues from db.profile in core
end

function module:OnBtnAddonComms(wndHandler, wndControl)
	core.db.profile.bAddonComms = wndControl:IsChecked()
	core:DbProfileUpdate() -- needed to refresh upvalues from db.profile in core
end

function module:OnBtnLegacySupport(wndHandler, wndControl)
	core.db.profile.bLegacySupport = wndControl:IsChecked()
	core:DbProfileUpdate() -- needed to refresh upvalues from db.profile in core
end

function module:OnBtnAutoAccept(wndHandler, wndControl)
	core.db.profile.bAutoAccept = wndControl:IsChecked()
	core:DbProfileUpdate() -- needed to refresh upvalues from db.profile in core
end

function module:OnBtnAutoDecline(wndHandler, wndControl)
	core.db.profile.bAutoDecline = wndControl:IsChecked()
	core:DbProfileUpdate() -- needed to refresh upvalues from db.profile in core
end

function module:OnBtnNoDeclineGuild(wndHandler, wndControl)
	core.db.profile.bNoDeclineGuild = wndControl:IsChecked()
	core:DbProfileUpdate() -- needed to refresh upvalues from db.profile in core
end

function module:OnBtnReset(wndHandler, wndControl)
	core.db:ResetProfile()
end

function module:OnBtnSetShareRatio(wndHandler, wndControl)
	if wndHandler ~= wndControl or addonHousingRemodel == nil then return end

	if not ( HousingLib:IsHousingWorld() and HousingLib:IsOnMyResidence() and not HousingLib:IsWarplotResidence() ) then
		core:Print('You need to be on Your housing plot to do that.')
		return
	end
	addonHousingRemodel:OnPropertySettingsBtn( wndHandler, wndControl)
end

function module:Toggle()
	wndSettings:Show(not wndSettings:IsShown())
end
