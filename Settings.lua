
local Apollo, XmlDoc, HousingLib, Print = Apollo, XmlDoc, HousingLib, Print

local core = Apollo.GetAddon("WYBMNRedux")
local module = core:NewModule("Settings")

local wndSettings

local function dbProfileUpdate()
	wndSettings:FindChild("btnAutoToggle"):SetCheck(core.db.profile.bAutoToggle)
	wndSettings:FindChild("btnAddonComms"):SetCheck(core.db.profile.bAddonComms)
	wndSettings:FindChild("btnLegacySupport"):SetCheck(core.db.profile.bLegacySupport)
	wndSettings:FindChild("btnAutoAccept"):SetCheck(core.db.profile.bAutoAccept)
	wndSettings:FindChild("btnAutoDecline"):SetCheck(core.db.profile.bAutoDecline)
	wndSettings:FindChild("btnNoDeclineGuild"):SetCheck(core.db.profile.bNoDeclineGuild)
end

function module:OnInitialize()
	self.xmlDoc = XmlDoc.CreateFromFile("Settings.xml")
	
	core.db.RegisterCallback(self.Name, "OnProfileReset", dbProfileUpdate)
	core.db.RegisterCallback(self.Name, "OnProfileChanged", dbProfileUpdate)
	core.db.RegisterCallback(self.Name, "OnProfileCopied", dbProfileUpdate)
end

function module:OnEnable()
	wndSettings = Apollo.LoadForm(self.xmlDoc, "WYBMNReduxSettings", nil, self)
	wndSettings:Show(false)

	dbProfileUpdate()
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


do
	local function crbSettingsCancel( self, wndHandler, wndControl, eMouseButton )
		if wndHandler:GetId() ~= wndControl:GetId() then
			return
		end
		self.wndPropertySettingsPopup:Show(false)
		
		if HousingLib:IsHousingWorld() and HousingLib:IsOnMyResidence() and not HousingLib:IsWarplotResidence() then
			core:UpdateOwnData()
			core:UpdateCurrentPlot()
		end
	end
	function module:OnBtnSetShareRatio(wndHandler, wndControl)
		if wndHandler ~= wndControl then
			return
		end

		if not ( HousingLib:IsHousingWorld() and HousingLib:IsOnMyResidence() and not HousingLib:IsWarplotResidence() ) then
			Print('WYBMNRedux: You need to be on Your housing plot to do that.')
			return
		end

		local crbRemodel = Apollo.GetAddon('HousingRemodel')
		crbRemodel.OnSettingsCancel = crbSettingsCancel
		crbRemodel:OnPropertySettingsBtn( wndHandler, wndControl)
	end
end
function module:Toggle()
	wndSettings:Show(not wndSettings:IsShown())
end
