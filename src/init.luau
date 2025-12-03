--!strict
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local CheckRequestBudget = require(script.CheckRequestBudget)

local TestSuccess = pcall(function()
	repeat
		task.wait(.1)
	until CheckRequestBudget("Set", 1)
	
	local TestStore = DataStoreService:GetDataStore("-")
	TestStore:SetAsync("1", "Hello")
end)

if not TestSuccess then
	error("DataStoreService is not enabled.")
	return
end

local Types = require(script.Types)
local Processor = require(script.Processor)

local Sift = require(script.Parent.Sift) :: { [string]: any }
local Signal = require(script.Parent.Signal) :: { [string]: any }
local Promise = require(script.Parent.Promise) :: { [string]: any }

local function NOOP() end
local Array = Sift.Array

local ScoreSync = {}
ScoreSync.__index = ScoreSync

--[=[
    @prop Updated Signal
    @within ScoreSync
]=]

--[=[
	@function new
	@within ScoreSync
	@param Config { Name: string, UTC: number?, Type: ("Highest" | "Lowest")?, Cycle: ("All-Time" | "Yearly" | "Quarterly" | "Monthly" | "Daily" | "Hourly")?, CycleDay: ("Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday")?, Refresh: number?, Version: number?, BatchOverrides: { Size: number?, Delay: number? }? }
	@return ScoreSync

	Creates a new ScoreSync object.
	- `Name` (string): The name of the leaderboard.
	- `UTC` (number, optional): The UTC offset for the leaderboard. Defaults to 0. (Note this is in hours)
	- `Type` (string, optional): The type of leaderboard (Highest or Lowest). Defaults to 'Highest'.
	- `Cycle` (string, optional): The cycle of the leaderboard, Options: ('All-Time', 'Yearly', 'Quarterly', 'Monthly', 'Weekly', 'Daily', 'Hourly'). Defaults to 'All-Time'.
	- `CycleDay` (string, optional): The day of the week to reset the leaderboard. Defaults to 'Friday'.
	- `Refresh` (number, optional): The refresh rate of the leaderboard. Defaults to 60.
	- `Version` (number, optional): The version of the leaderboard. Defaults to 1.
	- `Predicate` (function, optional): The predicate function to filter the players, if true the player will be included in the leaderboard. Defaults to nil.
	- `BatchOverrides` (table, optional): The batch overrides for the Processor.
		- `Size` (number, optional): The number of requests to process at once. Defaults to 20
		- `Delay` (number, optional): The delay between each batch. Defaults to 30
]=]

--[=[
    @class ScoreSync
    Leaderboard object (ScoreSync) for managing player scores.
]=]

local DayToNumberLookup = {
	Sunday = 3,
	Monday = 2,
	Tuesday = 1,
	Wednesday = 0,
	Thursday = -1,
	Friday = -2,
	Saturday = -3,
}

function ScoreSync.new(Config: Types.Config)
	local Name = if RunService:IsStudio() then "Mock" .. Config.Name else Config.Name
	local Order = Config.Type or "Highest"
	local Refresh = Config.Refresh or 60
	local Version = Config.Version or 1
	local UTCOffset = if Config.UTC then Config.UTC * 3600 else 0

	local Cycle = Config.Cycle or "All-Time"
	local Current = nil
	local Interval = math.huge
	local DataStore = nil
	local DayOffset = DayToNumberLookup[Config.CycleDay or "Friday"] * 86400

	if Cycle ~= "All-Time" then
		local Time = DateTime.now().UnixTimestamp + DayOffset + UTCOffset

		if Cycle == "Yearly" then
			Interval = 31536000
		elseif Cycle == "Quarterly" then
			Interval = 7884000
		elseif Cycle == "Monthly" then
			Interval = 2628000
		elseif Cycle == "Weekly" then
			Interval = 604800
		elseif Cycle == "Daily" then
			Interval = 86400
		elseif Cycle == "Hourly" then
			Interval = 3600
		end

		Current = math.floor(Time / Interval)
	end

	local function Callback(QueuedEvent: Types.Process): boolean
		if not DataStore then
			return false
		end

		local Success, Data = pcall(DataStore.UpdateAsync, DataStore, QueuedEvent.Key, function(Value: number | nil)
			return if QueuedEvent.Event == "Increment" then math.floor((Value or 0) + QueuedEvent.Value)
				else if Order == "Highest"
				then if not Value then math.floor(QueuedEvent.Value) else math.max(math.floor(Value), math.floor(QueuedEvent.Value))
				else if not Value then math.floor(QueuedEvent.Value) else math.min(math.floor(Value), math.floor(QueuedEvent.Value))
		end)

		if not Success then
			warn(`Failed to update {QueuedEvent.Key} with {QueuedEvent.Value}`)
		end

		return Success
	end

	DataStore = DataStoreService:GetOrderedDataStore(
		`[Score-Sync]{Name}-{Version}`,
		`{if Cycle == "All-Time" then "All-Time" else Cycle .. ":" .. Current}`
	)

	local self = setmetatable({
		_Cache = {} :: {},
		_Start = tick() - Refresh,
		_Order = Order,
		_Status = "Failed",
		Updated = Signal.new(),
		_Refresh = Refresh,
		_Interval = Interval,
		_DataStore = DataStore :: OrderedDataStore,
		_Processor = Processor.new(Callback, Config.BatchOverrides),
		_UTCOffset = UTCOffset,
		_DayOffset = DayOffset,
		_Predicate = Config.Predicate,
		StatusChanged = Signal.new(),
	}, ScoreSync)

	self._Thread = task.spawn(function()
		while task.wait(1) do
			if Cycle ~= "All-Time" then
				local Time = DateTime.now().UnixTimestamp + DayOffset + UTCOffset
				local Key = math.floor(Time / Interval)
	
				if Key ~= Current then
					Current = Key
					DataStore = DataStoreService:GetOrderedDataStore(`{Name}-{Cycle}:{Current}`)
					self._Cache = {}
					self._DataStore = DataStore
				end
			end

			local CurrentTime = tick()
			if CurrentTime - self._Start >= Refresh then
				local _ = self:GetOrderedListAsync():catch(NOOP)
			end
		end
	end)

	return self
end

--[=[
    @method TimeUntilReset
    @within ScoreSync
    @param AsString boolean?
    @return number | string
]=]
function ScoreSync:TimeUntilReset(AsString: boolean?): number | string
	if self._Interval == math.huge then
		return if AsString then "N/A" else math.huge
	end

	local Time = os.time() + self._DayOffset + self._UTCOffset
	local Remaining = self._Interval - math.floor(Time % self._Interval)
	
	return if AsString
		then string.format(
			"%02d:%02d:%02d:%02d",
			math.floor(Remaining / 86400),
			math.floor(Remaining / 3600) % 24,
			Remaining / 60 % 60,
			Remaining % 60
		)
		else Remaining
end

--[=[
    @method IncrementAsync
    @within ScoreSync
    @param Player Player
    @param Amount number?
    @return Promise<boolean>
]=]
function ScoreSync:IncrementAsync(Player: Player, Amount: number?)
	if self._Predicate and not self._Predicate(Player) then
		return Promise.resolve(false)
	end

	if not Amount then
		Amount = 1
	end

	local Index = Sift.Array.findWhere(self._Cache, function(Item)
		return Item.key == tostring(Player.UserId)
	end)

	if Index then
		self._Cache[Index].value += Amount
	else
		if #self._Cache < 100 then
			table.insert(self._Cache, {
				key = tostring(Player.UserId),
				value = Amount,
			})
		end
	end

	table.sort(self._Cache, function(A, B)
		return if self._Order == "Highest" then A.value > B.value else A.value < B.value
	end)

	self.Updated:Fire(self._Cache)

	return Promise.resolve(self._Processor:Add({
		Time = os.time(),
		Event = "Increment",
		Value = Amount,
		Key = tostring(Player.UserId),
	}))
end

--[=[
    @method SetAsync
    @within ScoreSync
    @param Player Player
    @param Amount number
    @return Promise<boolean>
]=]
function ScoreSync:SetAsync(Player: Player, Value: number)
	if self._Predicate and not self._Predicate(Player) then
		return Promise.resolve(false)
	end

	local Index = Sift.Array.findWhere(self._Cache, function(Item)
		return Item.key == tostring(Player.UserId)
	end)

	if Index then
		local value = self._Cache[Index].value
		self._Cache[Index].value = if self._Order == "Highest"
			then math.max(Value, value)
			else math.min(Value, value)
	else
		if #self._Cache < 100 then
			table.insert(self._Cache, {
				key = tostring(Player.UserId),
				value = Value,
			})
		end
	end

	table.sort(self._Cache, function(A, B)
		return if self._Order == "Highest" then A.value > B.value else A.value < B.value
	end)

	self.Updated:Fire(self._Cache)

	return Promise.resolve(self._Processor:Add({
		Time = os.time(),
		Event = "Set",
		Value = Value,
		Key = tostring(Player.UserId),
	}))
end

--[=[
    @type Result (key: string, value: number)
    @within ScoreSync

    An object containing the key and value of a score.
]=]

--[=[
    @method GetOrderedListAsync
    @within ScoreSync
    @param Count number?
    @param Min number?
    @param Max number?
    @return Promise<{ Result? }>
]=]
type Promise<T> = typeof(Promise.new())

type Result = { key: string, value: number }

function ScoreSync:GetOrderedListAsync(
	Count: number?,
	Min: number?,
	Max: number?
): Promise<{ Result? }>
	local CanRefresh = tick() - self._Start >= self._Refresh

	Count = Count or 100

	if not CanRefresh and not Min and not Max then
		return Promise.resolve(Array.filter(self._Cache, function(_, Index)
			return Index <= Count
		end))
	end

	local List = {} :: { Result? }

	if CheckRequestBudget("Get", 1) then
		self._Start = tick()
		local _Success, Pages = pcall(self._DataStore.GetSortedAsync, self._DataStore, self._Order ~= "Highest", Count, Min, Max)
		
		if _Success and Pages and typeof(Pages) ~= "string" then
			local CurrentPage = Pages:GetCurrentPage()
			List = table.clone(CurrentPage)

			if not Min and not Max and not Array.equalsDeep(List, self._Cache) then -- only update cache when no value range is defined and the list is different
				self._Cache = table.clone(List)
				self.Updated:Fire(self._Cache)
			end
		end

		if _Success and self._Status ~= "Success" then
			self._Status = "Success"
			self.StatusChanged:Fire(self._Status)
		end
	elseif self._Status ~= "Failed" then
		if Min and Max and Min < #List and Max < #List then
			table.move(self._Cache, Min, Max, 1, List)
		else
			List = table.clone(self._Cache)
		end

		self._Status = "Failed"
		self.StatusChanged:Fire(self._Status)
	end

	return Promise.resolve(List)
end

function ScoreSync:Destroy()
	if self._Thread and coroutine.status(self._Thread) ~= "dead" then
		task.cancel(self._Thread)
		self._Thread = nil
	end

	table.clear(self)
end

return ScoreSync