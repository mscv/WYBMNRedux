local Apollo, XmlDoc = Apollo, XmlDoc
local next = next

local core = Apollo.GetAddon('WYBMNRedux')
local module = core:NewModule('Search')

local wndSearch, wndGrid, wndNodeType, wndNodeLevel, wndShareRatio
local tNodeType2Name, tShares

function module:OnInitialize()
	self.xmlDoc = XmlDoc.CreateFromFile('Search.xml')

	tNodeType2Name = core.tNodeType2Name
	tShares = core.tShares
end

function module:OnEnable()
	wndSearch = Apollo.LoadForm(module.xmlDoc, 'WYBMNReduxSearch', nil, module)
	wndSearch:Show(false)
	
	wndGrid			= wndSearch:FindChild('wndSearch'):FindChild('wndGrid')
	wndNodeType		= wndSearch:FindChild('wndSettings'):FindChild('wndNodeType')
	wndNodeLevel	= wndSearch:FindChild('wndSettings'):FindChild('wndNodeLevel')
	wndShareRatio	= wndSearch:FindChild('wndSettings'):FindChild('wndShareRatio')

	wndNodeType:SetRadioSel('NodeType', core.db.char.filterNodeType)
	wndNodeLevel:SetRadioSel('NodeLevel', core.db.char.filterNodeLevel)
	wndShareRatio:SetRadioSel('ShareRatio', core.db.char.filterShareRatio + 1)
end

function module:Toggle()
	local bVisible = wndSearch:IsShown()
	wndSearch:Show(not bVisible)
	if not bVisible then -- a lil gotcha :)
		self:GridRefresh()
	end
end

function module:GridRefresh()
	wndGrid:DeleteAll()

	for k,v in next, core:GetOnlineUsersFiltered() do
		local newRow = wndGrid:AddRow(k) -- terribly dumb, adding a row only sets 1st column text ...
		wndGrid:SetCellText(newRow, 2, tShares[v.shareRatio])
		wndGrid:SetCellText(newRow, 3, tNodeType2Name[v.nodeType])
	end
	wndGrid:SetSortColumn(1, true)
end

function module:OnRadioNodeType()
	core.db.char.filterNodeType = wndNodeType:GetRadioSel('NodeType')
	self:GridRefresh()
end

function module:OnRadioNodeLevel()
	core.db.char.filterNodeLevel = wndNodeLevel:GetRadioSel('NodeLevel')
	self:GridRefresh()
end

function module:OnRadioShareRatio()
	core.db.char.filterShareRatio = wndShareRatio:GetRadioSel('ShareRatio') - 1
	self:GridRefresh()
end

function module:OnBtnAddAll()
	local iNumRows = wndGrid:GetRowCount()
	for i = 1, iNumRows do
		core:NeighbourAdd( wndGrid:GetCellText(i,1) )
	end
end

function module:OnBtnAddSelected()
	local iRow = wndGrid:GetCurrentRow()
	if iRow then
		core:NeighbourAdd( wndGrid:GetCellText(iRow,1) )
	end
end
