--!strict
--!optimize 2

export type LayoutMode = "Grid" | "List"
export type ScrollAlignment = "Top" | "Center" | "Bottom"

type ContentPaddingValue = UDim | number

type ContentPadding = {
	left: ContentPaddingValue,
	right: ContentPaddingValue,
	top: ContentPaddingValue,
	bottom: ContentPaddingValue,
}

type ContentPaddingPatch = {
	left: ContentPaddingValue?,
	right: ContentPaddingValue?,
	top: ContentPaddingValue?,
	bottom: ContentPaddingValue?,
}

export type LayoutConfig = {
	type: LayoutMode,
	itemSize: UDim2,
	itemPadding: UDim2,
	maxItemsPerRow: number?,
	autoFit: boolean,
	horizontalAlignment: Enum.HorizontalAlignment,
	verticalAlignment: Enum.VerticalAlignment,
	contentPadding: ContentPadding,
}

export type LayoutPatch = {
	type: LayoutMode?,
	itemSize: UDim2?,
	itemPadding: UDim2?,
	maxItemsPerRow: number?,
	autoFit: boolean?,
	horizontalAlignment: Enum.HorizontalAlignment?,
	verticalAlignment: Enum.VerticalAlignment?,
	contentPadding: ContentPaddingPatch?,
}

type Metrics = {
	itemCount: number,
	viewportX: number,
	viewportY: number,
	insetLeft: number,
	insetRight: number,
	insetTop: number,
	insetBottom: number,
	innerWidth: number,
	innerHeight: number,
	itemWidth: number,
	itemHeight: number,
	padX: number,
	padY: number,
	itemsPerRow: number,
	rowCount: number,
	rowSpan: number,
	contentHeight: number,
	contentBaseY: number,
	horizontalFactor: number,
	canvasHeight: number,
	desiredActiveFrames: number,
}

export type ItemRect = {
	row: number,
	column: number,
	x: number,
	y: number,
	width: number,
	height: number,
}

export type ScrollAnimationContext<T> = {
	virtualizedUI: VirtualizedUI<T>,
	scrollingFrame: ScrollingFrame,
	fromPosition: Vector2,
	toPosition: Vector2,
	duration: number,
	index: number,
	alignment: ScrollAlignment,
}

export type ScrollAnimator<T> = (
	context: ScrollAnimationContext<T>,
	onComplete: () -> ()
) -> (() -> ())?

export type onApplyDataFn<T> = (frame: GuiObject, dataItem: T, index: number) -> ()
export type onItemSetupFn<T> = (frame: GuiObject, virtualizedUI: VirtualizedUI<T>) -> ()
export type onItemShownFn<T> = (index: number, frame: GuiObject, dataItem: T) -> ()
export type onItemHiddenFn = (index: number, frame: GuiObject) -> ()
export type onScrolledFn = (canvasY: number) -> ()

export type VirtualizedUI<T> = {
	UpdateCanvasSize: (self: VirtualizedUI<T>) -> (),
	UpdateVisibleItems: (self: VirtualizedUI<T>) -> (),
	GetVisibleItemCount: (self: VirtualizedUI<T>) -> number,
	GetItemsPerRow: (self: VirtualizedUI<T>) -> number,
	GetRowCount: (self: VirtualizedUI<T>) -> number,
	GetItemRect: (self: VirtualizedUI<T>, index: number) -> ItemRect?,
	ReloadData: (self: VirtualizedUI<T>, newData: { T }?) -> (),
	SetLayout: (self: VirtualizedUI<T>, patch: LayoutPatch) -> (),
	ReplaceLayout: (self: VirtualizedUI<T>, layout: LayoutConfig) -> (),
	SetScrollAnimator: (self: VirtualizedUI<T>, scrollAnimator: ScrollAnimator<T>) -> (),
	SetScrollAnimationDuration: (self: VirtualizedUI<T>, duration: number) -> (),
	Refresh: (self: VirtualizedUI<T>) -> (),
	ScrollToIndex: (
		self: VirtualizedUI<T>,
		index: number,
		animated: boolean?,
		alignment: ScrollAlignment?
	) -> (),
	SortData: (self: VirtualizedUI<T>, comparator: (T, T) -> boolean) -> (),
	AddItem: (self: VirtualizedUI<T>, dataItem: T, position: number?) -> (),
	RemoveItem: (self: VirtualizedUI<T>, index: number) -> (),
	Destroy: (self: VirtualizedUI<T>) -> (),
}

export type Options<T> = {
	scrollingFrame: ScrollingFrame,
	itemTemplate: GuiObject,

	layout: LayoutConfig,
	bufferRows: number,
	maxPoolSize: number,

	scrollAnimationDuration: number,
	scrollAnimator: ScrollAnimator<T>,

	data: { T }?,
	getItemCount: (() -> number)?,
	getItem: ((number) -> T?)?,

	onApplyData: onApplyDataFn<T>,
	onItemSetup: onItemSetupFn<T>?,
	onItemShown: onItemShownFn<T>?,
	onItemHidden: onItemHiddenFn?,
	onScrolled: onScrolledFn?,
	scrollBarThickness: number?,
}

type State<T> = {
	scrollingFrame: ScrollingFrame,
	itemTemplate: GuiObject,

	data: { T },
	getItemCount: (() -> number)?,
	getItem: ((number) -> T?)?,

	layout: LayoutConfig,
	bufferRows: number,
	maxPoolSize: number,

	onApplyData: onApplyDataFn<T>,
	onItemSetup: onItemSetupFn<T>?,
	onItemShown: onItemShownFn<T>?,
	onItemHidden: onItemHiddenFn?,
	onScrolled: onScrolledFn?,

	scrollAnimationDuration: number,
	scrollAnimator: ScrollAnimator<T>,
	activeScrollCancel: (() -> ())?,

	framePool: { GuiObject },
	activeFrames: { [number]: GuiObject },
	totalFrames: number,

	isUpdating: boolean,
	layoutDirty: boolean,
	metrics: Metrics?,
	visibleStartIndex: number?,
	visibleEndIndex: number?,

	scrollConnection: RBXScriptConnection?,
	resizeConnection: RBXScriptConnection?,
}

local function resolveUDim(value: ContentPaddingValue, base: number): number
	if typeof(value) == "UDim" then
		return (value :: UDim).Scale * base + (value :: UDim).Offset
	else
		return value
	end
end

local function resolveItemsPerRow(layout: LayoutConfig, innerWidth: number, itemWidth: number, padX: number): number
	if layout.type == "List" then
		return 1
	elseif layout.autoFit then
		local slotWidth = itemWidth + padX
		if slotWidth <= 0 then
			return 1
		end
		return math.max(1, math.floor((innerWidth + padX) / slotWidth))
	else
		return math.max(1, layout.maxItemsPerRow or 1)
	end
end

local function cancelScrollAnimation<T>(self: State<T>)
	local cancel = self.activeScrollCancel

	if cancel then
		self.activeScrollCancel = nil
		cancel()
	end
end

local function getItemCount<T>(self: State<T>): number
	local getter = self.getItemCount

	if getter then
		return math.max(0, math.floor(getter()))
	else
		return #self.data
	end
end

local function getItem<T>(self: State<T>, index: number): T?
	local getter = self.getItem

	if getter then
		return getter(index)
	else
		return self.data[index]
	end
end

local function supportsArrayMutation<T>(self: State<T>): boolean
	return self.getItemCount == nil and self.getItem == nil
end

local function getRowItemCount(rowIndex: number, metrics: Metrics): number
	local firstIndex = rowIndex * metrics.itemsPerRow + 1
	local lastIndex = math.min(metrics.itemCount, firstIndex + metrics.itemsPerRow - 1)

	if lastIndex < firstIndex then
		return 0
	end

	return lastIndex - firstIndex + 1
end

local function getRowBaseX(rowItemCount: number, metrics: Metrics): number
	local rowWidth = rowItemCount * metrics.itemWidth + math.max(0, rowItemCount - 1) * metrics.padX
	local freeHorizontalSpace = math.max(0, metrics.innerWidth - rowWidth)
	return metrics.insetLeft + freeHorizontalSpace * metrics.horizontalFactor
end

local function getItemRect(index: number, metrics: Metrics): ItemRect?
	if index < 1 or index > metrics.itemCount then
		return nil
	end

	local row = math.floor((index - 1) / metrics.itemsPerRow)
	local column = (index - 1) % metrics.itemsPerRow
	local rowItemCount = getRowItemCount(row, metrics)

	return {
		row = row,
		column = column,
		x = getRowBaseX(rowItemCount, metrics) + column * (metrics.itemWidth + metrics.padX),
		y = metrics.contentBaseY + row * metrics.rowSpan,
		width = metrics.itemWidth,
		height = metrics.itemHeight,
	}
end

local function resolveMetrics<T>(self: State<T>): Metrics
	local itemCount = getItemCount(self)
	local viewportSize = self.scrollingFrame.AbsoluteSize
	local cached = self.metrics

	if cached
		and not self.layoutDirty
		and cached.itemCount == itemCount
		and cached.viewportX == viewportSize.X
		and cached.viewportY == viewportSize.Y
	then
		return cached
	end

	local layout = self.layout
	local padding = layout.contentPadding

	local insetLeft = math.max(0, resolveUDim(padding.left, viewportSize.X))
	local insetRight = math.max(0, resolveUDim(padding.right, viewportSize.X))
	local insetTop = math.max(0, resolveUDim(padding.top, viewportSize.Y))
	local insetBottom = math.max(0, resolveUDim(padding.bottom, viewportSize.Y))

	local innerWidth = math.max(0, viewportSize.X - insetLeft - insetRight)
	local innerHeight = math.max(0, viewportSize.Y - insetTop - insetBottom)

	local itemWidth = math.max(0, resolveUDim(layout.itemSize.X, innerWidth))
	local itemHeight = math.max(0, resolveUDim(layout.itemSize.Y, innerHeight))
	local padX = math.max(0, resolveUDim(layout.itemPadding.X, innerWidth))
	local padY = math.max(0, resolveUDim(layout.itemPadding.Y, innerHeight))

	local itemsPerRow = resolveItemsPerRow(layout, innerWidth, itemWidth, padX)
	local rowCount = if itemCount > 0 then math.ceil(itemCount / itemsPerRow) else 0

	local contentHeight = 0
	if rowCount > 0 then
		contentHeight = rowCount * itemHeight + math.max(0, rowCount - 1) * padY
	end

	local verticalFactor =
		if layout.verticalAlignment == Enum.VerticalAlignment.Center then 0.5
		elseif layout.verticalAlignment == Enum.VerticalAlignment.Bottom then 1
		else 0

	local freeVerticalSpace = math.max(0, innerHeight - contentHeight)
	local contentBaseY = insetTop + freeVerticalSpace * verticalFactor
	local contentBottomY = contentBaseY + contentHeight

	local rowSpan = itemHeight + padY
	local visibleRows = 0
	if rowSpan > 0 then
		visibleRows = math.ceil(viewportSize.Y / rowSpan)
	elseif rowCount > 0 then
		visibleRows = rowCount
	end

	local desiredActiveFrames = math.min(itemCount, math.max(0, visibleRows + self.bufferRows * 2 + 1) * itemsPerRow)
	local canvasHeight = math.max(viewportSize.Y, contentBottomY + insetBottom)

	local horizontalFactor =
		if layout.horizontalAlignment == Enum.HorizontalAlignment.Center then 0.5
		elseif layout.horizontalAlignment == Enum.HorizontalAlignment.Right then 1
		else 0

	local metrics: Metrics = {
		itemCount = itemCount,
		viewportX = viewportSize.X,
		viewportY = viewportSize.Y,
		insetLeft = insetLeft,
		insetRight = insetRight,
		insetTop = insetTop,
		insetBottom = insetBottom,
		innerWidth = innerWidth,
		innerHeight = innerHeight,
		itemWidth = itemWidth,
		itemHeight = itemHeight,
		padX = padX,
		padY = padY,
		itemsPerRow = itemsPerRow,
		rowCount = rowCount,
		rowSpan = rowSpan,
		contentHeight = contentHeight,
		contentBaseY = contentBaseY,
		horizontalFactor = horizontalFactor,
		canvasHeight = canvasHeight,
		desiredActiveFrames = desiredActiveFrames,
	}

	self.metrics = metrics
	self.layoutDirty = false
	return metrics
end

local function applyCanvasSizeFromMetrics<T>(self: State<T>, metrics: Metrics)
	local current = self.scrollingFrame.CanvasPosition
	local maxCanvasY = math.max(0, metrics.canvasHeight - metrics.viewportY)

	if current.Y > maxCanvasY then
		self.scrollingFrame.CanvasPosition = Vector2.new(current.X, maxCanvasY)
	end

	self.scrollingFrame.CanvasSize = UDim2.fromOffset(metrics.viewportX, metrics.canvasHeight)
end

local VirtualizedUI = {}
VirtualizedUI.__index = VirtualizedUI

local function createFrame<T>(self: State<T>): GuiObject
	local frame = self.itemTemplate:Clone()
	frame.Visible = false
	frame.Parent = self.scrollingFrame
	frame.Position = UDim2.fromOffset(0, 0)
	frame.Size = UDim2.fromOffset(0, 0)

	local onItemSetup = self.onItemSetup
	if onItemSetup then
		onItemSetup(frame, self :: VirtualizedUI<T>)
	end

	self.totalFrames += 1
	return frame
end

local function ensureFrameCapacity<T>(self: State<T>, targetTotalFrames: number)
	local desiredTotal = math.min(self.maxPoolSize, math.max(0, targetTotalFrames))
	while self.totalFrames < desiredTotal do
		table.insert(self.framePool, createFrame(self))
	end
end

local function takeFrame<T>(self: State<T>): GuiObject?
	local frame = table.remove(self.framePool)

	if frame then
		return frame
	elseif self.totalFrames < self.maxPoolSize then
		return createFrame(self)
	else
		return nil
	end
end

local function recycleFrame<T>(self: State<T>, index: number, frame: GuiObject)
	frame.Visible = false
	frame.Position = UDim2.fromOffset(0, 0)
	frame.Size = UDim2.fromOffset(0, 0)
	frame:SetAttribute("Index", nil)

	self.activeFrames[index] = nil
	table.insert(self.framePool, frame)

	local onItemHidden = self.onItemHidden
	if onItemHidden then
		onItemHidden(index, frame)
	end
end

local function applyFrameGeometry(frame: GuiObject, index: number, rect: ItemRect)
	frame.Position = UDim2.fromOffset(rect.x, rect.y)
	frame.Size = UDim2.fromOffset(rect.width, rect.height)
	frame.Visible = true
	frame:SetAttribute("Index", index)
end

function VirtualizedUI.new<T>(options: Options<T>): VirtualizedUI<T>
	local self = setmetatable({} :: State<T>, VirtualizedUI)

	self.scrollingFrame = options.scrollingFrame
	self.itemTemplate = options.itemTemplate

	self.data = options.data or {}
	self.getItemCount = options.getItemCount
	self.getItem = options.getItem

	self.layout = options.layout
	self.bufferRows = options.bufferRows
	self.maxPoolSize = options.maxPoolSize

	self.onApplyData = options.onApplyData
	self.onItemSetup = options.onItemSetup
	self.onItemShown = options.onItemShown
	self.onItemHidden = options.onItemHidden
	self.onScrolled = options.onScrolled

	self.scrollAnimationDuration = options.scrollAnimationDuration
	self.scrollAnimator = options.scrollAnimator

	self.framePool = {}
	self.activeFrames = {}
	self.totalFrames = 0

	self.isUpdating = false
	self.layoutDirty = true

	self.scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	self.scrollingFrame.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	self.scrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	self.scrollingFrame.ClipsDescendants = true

	if options.scrollBarThickness ~= nil then
		self.scrollingFrame.ScrollBarThickness = options.scrollBarThickness
	end

	self.itemTemplate.Visible = false

	self.scrollConnection = self.scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if not self.isUpdating then
			VirtualizedUI.UpdateVisibleItems(self)
		end

		local onScrolled = self.onScrolled
		if onScrolled then
			onScrolled(self.scrollingFrame.CanvasPosition.Y)
		end
	end)

	self.resizeConnection = self.scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self.layoutDirty = true
		if not self.isUpdating then
			VirtualizedUI.UpdateVisibleItems(self)
		end
	end)

	VirtualizedUI.UpdateVisibleItems(self)
	return (self :: VirtualizedUI<T>)
end

function VirtualizedUI.UpdateCanvasSize<T>(self: State<T>)
	applyCanvasSizeFromMetrics(self, resolveMetrics(self))
end

function VirtualizedUI.UpdateVisibleItems<T>(self: State<T>)
	if self.isUpdating then
		return
	end

	self.isUpdating = true

	local forceRefresh = self.layoutDirty or self.metrics == nil
	local metrics = resolveMetrics(self)
	applyCanvasSizeFromMetrics(self, metrics)

	if metrics.itemCount == 0 or metrics.itemsPerRow <= 0 or metrics.rowCount <= 0 or metrics.rowSpan <= 0 then
		self.visibleStartIndex = nil
		self.visibleEndIndex = nil

		local recycleList: { [number]: GuiObject } = {}
		for index, frame in self.activeFrames do
			recycleList[index] = frame
		end

		for index, frame in recycleList do
			recycleFrame(self, index, frame)
		end

		self.isUpdating = false
		return
	end

	ensureFrameCapacity(self, metrics.desiredActiveFrames + 4)

	local canvasY = self.scrollingFrame.CanvasPosition.Y
	local bufferPixels = self.bufferRows * metrics.rowSpan

	local startRow = math.max(0, math.floor((canvasY - metrics.contentBaseY - bufferPixels) / metrics.rowSpan))
	local endRow = math.min(
		metrics.rowCount - 1,
		math.floor((canvasY + metrics.viewportY - metrics.contentBaseY + bufferPixels - 1) / metrics.rowSpan)
	)

	if endRow < startRow then
		self.visibleStartIndex = nil
		self.visibleEndIndex = nil

		local recycleList: { [number]: GuiObject } = {}
		for index, frame in self.activeFrames do
			recycleList[index] = frame
		end

		for index, frame in recycleList do
			recycleFrame(self, index, frame)
		end

		self.isUpdating = false
		return
	end

	local startIndex = startRow * metrics.itemsPerRow + 1
	local endIndex = math.min(metrics.itemCount, (endRow + 1) * metrics.itemsPerRow)

	if not forceRefresh and self.visibleStartIndex == startIndex and self.visibleEndIndex == endIndex then
		self.isUpdating = false
		return
	end

	self.visibleStartIndex = startIndex
	self.visibleEndIndex = endIndex

	local recycleList: { [number]: GuiObject } = {}
	for index, frame in self.activeFrames do
		if index < startIndex or index > endIndex or getItem(self, index) == nil then
			recycleList[index] = frame
		end
	end

	for index, frame in recycleList do
		recycleFrame(self, index, frame)
	end

	for index = startIndex, endIndex do
		local dataItem = getItem(self, index)
		if dataItem ~= nil then
			local frame = self.activeFrames[index]
			local wasNew = false

			if not frame then
				frame = takeFrame(self)
				if not frame then
					break
				end
				self.activeFrames[index] = frame
				wasNew = true
			end

			local rect = getItemRect(index, metrics)
			if rect == nil then
				continue
			end

			local activeFrame = frame :: GuiObject
			applyFrameGeometry(activeFrame, index, rect)
			self.onApplyData(activeFrame, dataItem, index)

			if wasNew then
				local onItemShown = self.onItemShown
				if onItemShown then
					onItemShown(index, activeFrame, dataItem)
				end
			end
		end
	end

	self.isUpdating = false
end

function VirtualizedUI.GetVisibleItemCount<T>(self: State<T>): number
	local count = 0
	for _index, _frame in self.activeFrames do
		count += 1
	end
	return count
end

function VirtualizedUI.GetItemsPerRow<T>(self: State<T>): number
	return resolveMetrics(self).itemsPerRow
end

function VirtualizedUI.GetRowCount<T>(self: State<T>): number
	return resolveMetrics(self).rowCount
end

function VirtualizedUI.GetItemRect<T>(self: State<T>, index: number): ItemRect?
	return getItemRect(index, resolveMetrics(self))
end

function VirtualizedUI.ReloadData<T>(self: State<T>, newData: { T }?)
	if newData ~= nil then
		self.data = newData
	end
	self.layoutDirty = true
	VirtualizedUI.UpdateVisibleItems(self)
end

function VirtualizedUI.SetLayout<T>(self: State<T>, patch: LayoutPatch)
	local base = self.layout
	local basePadding = base.contentPadding
	local patchPadding = patch.contentPadding

	self.layout = {
		type = patch.type or base.type,
		itemSize = patch.itemSize or base.itemSize,
		itemPadding = patch.itemPadding or base.itemPadding,
		maxItemsPerRow = if patch.maxItemsPerRow ~= nil then patch.maxItemsPerRow else base.maxItemsPerRow,
		autoFit = if patch.autoFit ~= nil then patch.autoFit else base.autoFit,
		horizontalAlignment = patch.horizontalAlignment or base.horizontalAlignment,
		verticalAlignment = patch.verticalAlignment or base.verticalAlignment,
		contentPadding = {
			left = if patchPadding and patchPadding.left ~= nil then patchPadding.left else basePadding.left,
			right = if patchPadding and patchPadding.right ~= nil then patchPadding.right else basePadding.right,
			top = if patchPadding and patchPadding.top ~= nil then patchPadding.top else basePadding.top,
			bottom = if patchPadding and patchPadding.bottom ~= nil then patchPadding.bottom else basePadding.bottom,
		},
	}

	self.layoutDirty = true
	VirtualizedUI.UpdateVisibleItems(self)
end

function VirtualizedUI.ReplaceLayout<T>(self: State<T>, layout: LayoutConfig)
	self.layout = layout
	self.layoutDirty = true
	VirtualizedUI.UpdateVisibleItems(self)
end

function VirtualizedUI.SetScrollAnimator<T>(self: State<T>, scrollAnimator: ScrollAnimator<T>)
	cancelScrollAnimation(self)
	self.scrollAnimator = scrollAnimator
end

function VirtualizedUI.SetScrollAnimationDuration<T>(self: State<T>, duration: number)
	if duration <= 0 then
		return
	end
	self.scrollAnimationDuration = duration
end

function VirtualizedUI.Refresh<T>(self: State<T>)
	self.layoutDirty = true
	VirtualizedUI.UpdateVisibleItems(self)
end

function VirtualizedUI.ScrollToIndex<T>(self: State<T>, index: number, animated: boolean?, alignment: ScrollAlignment?)
	local metrics = resolveMetrics(self)
	local rect = getItemRect(index, metrics)
	if not rect then
		return
	end

	local mode = alignment or "Top"
	local targetY = rect.y

	if mode == "Center" then
		targetY = rect.y - math.max(0, (metrics.viewportY - rect.height) * 0.5)
	elseif mode == "Bottom" then
		targetY = rect.y - math.max(0, metrics.viewportY - rect.height)
	end

	local maxCanvasY = math.max(0, metrics.canvasHeight - metrics.viewportY)
	targetY = math.clamp(targetY, 0, maxCanvasY)

	local targetPosition = Vector2.new(self.scrollingFrame.CanvasPosition.X, targetY)

	if animated == true then
		cancelScrollAnimation(self)

		local done = false
		local function onComplete()
			if done then
				return
			end
			done = true
			self.activeScrollCancel = nil
		end

		local cancel = self.scrollAnimator({
			virtualizedUI = self :: VirtualizedUI<T>,
			scrollingFrame = self.scrollingFrame,
			fromPosition = self.scrollingFrame.CanvasPosition,
			toPosition = targetPosition,
			duration = self.scrollAnimationDuration,
			index = index,
			alignment = mode,
		}, onComplete)

		if not done then
			self.activeScrollCancel = cancel
		end
	else
		cancelScrollAnimation(self)
		self.scrollingFrame.CanvasPosition = targetPosition
	end
end

function VirtualizedUI.SortData<T>(self: State<T>, comparator: (T, T) -> boolean)
	if not supportsArrayMutation(self) then
		return
	end

	table.sort(self.data, comparator)
	self.layoutDirty = true
	VirtualizedUI.UpdateVisibleItems(self)
end

function VirtualizedUI.AddItem<T>(self: State<T>, dataItem: T, position: number?)
	if not supportsArrayMutation(self) then
		return
	end

	local insertPosition = position or (#self.data + 1)
	table.insert(self.data, insertPosition, dataItem)

	self.layoutDirty = true
	VirtualizedUI.UpdateVisibleItems(self)
end

function VirtualizedUI.RemoveItem<T>(self: State<T>, index: number)
	if not supportsArrayMutation(self) then
		return
	end

	if self.data[index] == nil then
		return
	end

	table.remove(self.data, index)
	self.layoutDirty = true
	VirtualizedUI.UpdateVisibleItems(self)
end

function VirtualizedUI.Destroy<T>(self: State<T>)
	if self.scrollConnection then
		self.scrollConnection:Disconnect()
		self.scrollConnection = nil
	end

	if self.resizeConnection then
		self.resizeConnection:Disconnect()
		self.resizeConnection = nil
	end

	cancelScrollAnimation(self)

	for i = 1, #self.framePool do
		self.framePool[i]:Destroy()
	end

	for _index, frame in self.activeFrames do
		frame:Destroy()
	end

	self.framePool = {}
	self.activeFrames = {}
	self.totalFrames = 0
	self.metrics = nil
end

return VirtualizedUI