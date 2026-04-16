--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VirtualizedUI = require("@game/ReplicatedStorage/Packages/VirtualizedUI")

type ItemData = {
	Name: string,
	Level: number,
	Multiplier: number,
}

type FrameRefs = {
	NameLabel: TextLabel,
	LevelLabel: TextLabel,
	MultiplierLabel: TextLabel,
}

type VirtualizedUIInstance<T=ItemData> = VirtualizedUI.VirtualizedUI<T>
type VirtualizedUIOptions<T=ItemData> = VirtualizedUI.Options<T>
type ScrollAnimationContext<T=ItemData> = VirtualizedUI.ScrollAnimationContext<T>
type ScrollAnimator<T=ItemData> = VirtualizedUI.ScrollAnimator<T>

local player = Players.LocalPlayer
if not player then
	return
end

local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local rng = Random.new()
local names = { "Alpha", "Bravo", "Comet", "Delta", "Echo", "Frost", "Glint", "Helix" }

local function makeData(count: number): { ItemData }
	local data = table.create(count) :: { ItemData }
	for i = 1, count do
		data[i] = {
			Name = names[rng:NextInteger(1, #names)] .. " #" .. tostring(i),
			Level = rng:NextInteger(1, 75),
			Multiplier = math.floor(rng:NextNumber(1.1, 4.0) * 10) / 10,
		}
	end
	return data
end

local function makeScrollAnimator(): ScrollAnimator<ItemData>
	return function(context: ScrollAnimationContext<ItemData>, onComplete: () -> ()): (() -> ())?
		local startPos = context.fromPosition
		local endPos = context.toPosition
		local duration = math.max(0.01, context.duration)

		local t = 0
		local canceled = false
		local conn: RBXScriptConnection? = nil

		conn = RunService.Heartbeat:Connect(function(dt)
			if canceled then
				if conn then
					conn:Disconnect()
				end
				return
			end

			t += dt
			local alpha = math.clamp(t / duration, 0, 1)
			local eased = 1 - (1 - alpha) * (1 - alpha)
			context.scrollingFrame.CanvasPosition = startPos:Lerp(endPos, eased)

			if alpha >= 1 then
				if conn then
					conn:Disconnect()
				end
				onComplete()
			end
		end)

		return function()
			canceled = true
			if conn then
				conn:Disconnect()
			end
		end
	end
end

local function makeLabel(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	pos: UDim2,
	align: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = Color3.fromRGB(20, 20, 20)
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.Size = size
	label.Position = pos
	label.Parent = parent
	return label
end

local function makeGridTemplate(parent: Instance): Frame
	local template = Instance.new("Frame")
	template.Name = "GridTemplate"
	template.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	template.BorderSizePixel = 0
	template.Visible = false
	template.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(230, 230, 230)
	stroke.Thickness = 1
	stroke.Parent = template

	local nameLabel = makeLabel(template, "NameLabel", "", UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, 6))
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15

	makeLabel(template, "LevelLabel", "", UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, 34))
	makeLabel(template, "MultiplierLabel", "", UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, 58))

	return template
end

local function makeListTemplate(parent: Instance): Frame
	local template = Instance.new("Frame")
	template.Name = "ListTemplate"
	template.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	template.BorderSizePixel = 0
	template.Visible = false
	template.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(230, 230, 230)
	stroke.Thickness = 1
	stroke.Parent = template

	local nameLabel = makeLabel(template, "NameLabel", "", UDim2.new(0.52, -10, 1, 0), UDim2.fromOffset(8, 0))
	nameLabel.Font = Enum.Font.GothamBold

	makeLabel(template, "LevelLabel", "", UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0.56, 0), Enum.TextXAlignment.Center)
	makeLabel(template, "MultiplierLabel", "", UDim2.new(0.24, -8, 1, 0), UDim2.fromScale(0.74, 0), Enum.TextXAlignment.Center)

	return template
end

local function makeSection(parent: Instance, titleText: string, pos: UDim2, size: UDim2): (Frame, ScrollingFrame)
	local section = Instance.new("Frame")
	section.BackgroundColor3 = Color3.fromRGB(247, 247, 247)
	section.BorderSizePixel = 0
	section.Position = pos
	section.Size = size
	section.Parent = parent

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.BorderSizePixel = 0
	title.Text = titleText
	title.TextColor3 = Color3.fromRGB(20, 20, 20)
	title.TextSize = 20
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -20, 0, 28)
	title.Position = UDim2.fromOffset(10, 8)
	title.Parent = section

	local scrolling = Instance.new("ScrollingFrame")
	scrolling.Name = titleText:gsub("%s+", "") .. "ScrollingFrame"
	scrolling.BackgroundTransparency = 1
	scrolling.BorderSizePixel = 0
	scrolling.Position = UDim2.fromOffset(10, 44)
	scrolling.Size = UDim2.new(1, -20, 1, -54)
	scrolling.ScrollBarThickness = 8
	scrolling.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 70)
	scrolling.ScrollBarImageTransparency = 0
	scrolling.CanvasSize = UDim2.fromOffset(0, 0)
	scrolling.Parent = section

	return section, scrolling
end

local function normalizeQuery(text: string): string
	local q = string.lower(text)
	q = string.gsub(q, "%s+", " ")
	q = string.gsub(q, "^%s+", "")
	q = string.gsub(q, "%s+$", "")
	return q
end

local function buildSearchText(item: ItemData): string
	local levelText = tostring(item.Level)
	local multiplierText = string.format("%.1f", item.Multiplier)
	local rawMultiplierText = tostring(item.Multiplier)

	return string.lower(table.concat({
		item.Name,
		levelText,
		"level " .. levelText,
		"level: " .. levelText,
		"lv " .. levelText,
		multiplierText,
		rawMultiplierText,
		"x" .. multiplierText,
		"multiplier " .. multiplierText,
		"multiplier: " .. multiplierText,
		"multiplier x" .. multiplierText,
		"multiplier: x" .. multiplierText,
	}, " "))
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VirtualizedExampleUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(960, 580)
root.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
root.BorderSizePixel = 0
root.Parent = screenGui

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 18)
padding.PaddingBottom = UDim.new(0, 18)
padding.PaddingLeft = UDim.new(0, 18)
padding.PaddingRight = UDim.new(0, 18)
padding.Parent = root

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.BorderSizePixel = 0
title.Text = "Virtualized Grid + List"
title.TextColor3 = Color3.fromRGB(20, 20, 20)
title.TextSize = 24
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Size = UDim2.fromOffset(520, 32)
title.Parent = root

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.Position = UDim2.fromOffset(0, 40)
searchBox.Size = UDim2.new(1, 0, 0, 34)
searchBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
searchBox.BorderSizePixel = 0
searchBox.TextColor3 = Color3.fromRGB(20, 20, 20)
searchBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 130)
searchBox.PlaceholderText = "Search by name, level, multiplier..."
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.TextSize = 14
searchBox.Font = Enum.Font.Gotham
searchBox.ClearTextOnFocus = false
searchBox.Parent = root

local searchPadding = Instance.new("UIPadding")
searchPadding.PaddingLeft = UDim.new(0, 10)
searchPadding.PaddingRight = UDim.new(0, 10)
searchPadding.Parent = searchBox

local searchStroke = Instance.new("UIStroke")
searchStroke.Color = Color3.fromRGB(230, 230, 230)
searchStroke.Thickness = 1
searchStroke.Parent = searchBox

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(0, 84)
body.Size = UDim2.new(1, 0, 1, -84)
body.Parent = root

local _, gridScrollingFrame = makeSection(body, "Grid", UDim2.fromScale(0, 0), UDim2.fromScale(0.58, 1))
local _, listScrollingFrame = makeSection(body, "List", UDim2.fromScale(0.60, 0), UDim2.fromScale(0.40, 1))

local gridTemplate = makeGridTemplate(gridScrollingFrame)
local listTemplate = makeListTemplate(listScrollingFrame)

local allData = makeData(1_000_000)
local filteredData: { ItemData } = allData

local searchIndex = table.create(#allData, "") :: { string }
for i = 1, #allData do
	searchIndex[i] = buildSearchText(allData[i])
end

local scrollAnimator: ScrollAnimator<ItemData> = makeScrollAnimator()

local gridRefs: { [GuiObject]: FrameRefs } = {}
local listRefs: { [GuiObject]: FrameRefs } = {}

local function cacheRefs(frame: GuiObject, store: { [GuiObject]: FrameRefs })
	local nameLabel = frame:FindFirstChild("NameLabel")
	local levelLabel = frame:FindFirstChild("LevelLabel")
	local multiplierLabel = frame:FindFirstChild("MultiplierLabel")

	if not (nameLabel and nameLabel:IsA("TextLabel")) then
		return
	end
	if not (levelLabel and levelLabel:IsA("TextLabel")) then
		return
	end
	if not (multiplierLabel and multiplierLabel:IsA("TextLabel")) then
		return
	end

	store[frame] = {
		NameLabel = nameLabel,
		LevelLabel = levelLabel,
		MultiplierLabel = multiplierLabel,
	}
end

local gridOptions: VirtualizedUIOptions<ItemData> = {
	scrollingFrame = gridScrollingFrame,
	itemTemplate = gridTemplate,
	data = filteredData,

	layout = {
		type = "Grid",
		itemSize = UDim2.fromOffset(165, 100),
		itemPadding = UDim2.fromOffset(10, 10),
		maxItemsPerRow = 3,
		autoFit = false,
		horizontalAlignment = Enum.HorizontalAlignment.Left,
		verticalAlignment = Enum.VerticalAlignment.Top,
		contentPadding = {
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
		},
	},

	bufferRows = 3,
	maxPoolSize = 250,
	scrollIdleDelay = 0.08,
	scrollAnimationDuration = 0.2,
	scrollAnimator = scrollAnimator,

	onItemSetup = function(frame: GuiObject, _virtualizedUI)
		cacheRefs(frame, gridRefs)
	end,

	onApplyData = function(frame: GuiObject, dataItem: ItemData, index: number)
		local refs = gridRefs[frame]
		if not refs then
			cacheRefs(frame, gridRefs)
			refs = gridRefs[frame]
			if not refs then
				return
			end
		end

		refs.NameLabel.Text = dataItem.Name
		refs.LevelLabel.Text = "Level: " .. tostring(dataItem.Level)
		refs.MultiplierLabel.Text = "Multiplier: x" .. string.format("%.1f", dataItem.Multiplier)

		frame.Name = "GridItem_" .. tostring(index)
		frame.BackgroundColor3 = if index % 2 == 0 then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(252, 252, 252)
	end,

	onItemHidden = function(_index: number, frame: GuiObject)
		gridRefs[frame] = nil
	end,
}

local listOptions: VirtualizedUIOptions<ItemData> = {
	scrollingFrame = listScrollingFrame,
	itemTemplate = listTemplate,
	data = filteredData,

	layout = {
		type = "List",
		itemSize = UDim2.new(1, 0, 0, 56),
		itemPadding = UDim2.fromOffset(0, 8),
		maxItemsPerRow = 1,
		autoFit = false,
		horizontalAlignment = Enum.HorizontalAlignment.Left,
		verticalAlignment = Enum.VerticalAlignment.Top,
		contentPadding = {
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
		},
	},

	bufferRows = 6,
	maxPoolSize = 280,
	scrollIdleDelay = 0.08,
	scrollAnimationDuration = 0.2,
	scrollAnimator = scrollAnimator,

	onItemSetup = function(frame: GuiObject, _virtualizedUI)
		cacheRefs(frame, listRefs)
	end,

	onApplyData = function(frame: GuiObject, dataItem: ItemData, index: number)
		local refs = listRefs[frame]
		if not refs then
			cacheRefs(frame, listRefs)
			refs = listRefs[frame]
			if not refs then
				return
			end
		end

		refs.NameLabel.Text = dataItem.Name
		refs.LevelLabel.Text = "Lv " .. tostring(dataItem.Level)
		refs.MultiplierLabel.Text = "x" .. string.format("%.1f", dataItem.Multiplier)

		frame.Name = "ListItem_" .. tostring(index)
		frame.BackgroundColor3 = if index % 2 == 0 then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(252, 252, 252)
	end,

	onItemHidden = function(_index: number, frame: GuiObject)
		listRefs[frame] = nil
	end,
}

local gridScroller = VirtualizedUI.new(gridOptions)
local listScroller = VirtualizedUI.new(listOptions)

local function applySearch(rawQuery: string)
	local query = normalizeQuery(rawQuery)
	local nextData: { ItemData } = {}

	if query == "" then
		nextData = allData
	else
		for i = 1, #allData do
			if string.find(searchIndex[i], query, 1, true) ~= nil then
				nextData[#nextData + 1] = allData[i]
			end
		end
	end

	filteredData = nextData
	gridScroller:ReloadData(filteredData)
	listScroller:ReloadData(filteredData)

	gridScrollingFrame.CanvasPosition = Vector2.new(0, 0)
	listScrollingFrame.CanvasPosition = Vector2.new(0, 0)
end

local searchConn = searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	applySearch(searchBox.Text)
end)

gridScroller:Refresh()
listScroller:Refresh()

script.Destroying:Connect(function()
	searchConn:Disconnect()
	gridScroller:Destroy()
	listScroller:Destroy()
end)