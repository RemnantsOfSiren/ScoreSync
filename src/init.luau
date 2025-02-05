--!strict
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local TestSuccess = pcall(function()
	local TestStore = DataStoreService:GetDataStore("-")
	TestStore:SetAsync("1", "Hello")
end)

if not TestSuccess then
	error("DataStoreService is not enabled.")
	return
end

local Types = require(script.Types)
local Processor = require(script.Processor)
local CheckRequestBudget = require(script.CheckRequestBudget)

local Sift = require(script.Parent.Sift)
local Signal = require(script.Parent.Signal)
local Promise = require(script.Parent.Promise)

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
	@param Config { Name: string, UTC: number?, Type: ("Highest" | "Lowest")?, Cycle: ("All-Time" | "Yearly" | "Quarterly" | "Monthly" | "Daily" | "Hourly")?, CycleDay: ("Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday")?, Refresh: number?, BatchOverrides: { Size: number?, Delay: number? }? }
	@return ScoreSync

	Creates a new ScoreSync object.
	- `Name` (string): The name of the leaderboard.
	- `UTC` (number, optional): The UTC offset for the leaderboard. Defaults to 0. (Note this is in hours)
	- `Type` (string, optional): The type of leaderboard (Highest or Lowest). Defaults to 'Highest'.
	- `Cycle` (string, optional): The cycle of the leaderboard, Options: ('All-Time', 'Yearly', 'Quarterly', 'Monthly', 'Weekly', 'Daily', 'Hourly'). Defaults to 'All-Time'.
	- `CycleDay` (string, optional): The day of the week to reset the leaderboard. Defaults to 'Friday'.
	- `Refresh` (number, optional): The refresh rate of the leaderboard. Defaults to 60.
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
	local UTCOffset = if Config.UTC then Config.UTC * 3600 else 0

	local Cycle = Config.Cycle or "All-Time"
	local Current = nil
	local Interval = math.huge
	local DataStore = nil
	local DayOffset = DayToNumberLookup[Config.CycleDay or "Friday"] * 86400

	if Cycle ~= "All-Time" then
		local Time = os.time() + DayOffset + UTCOffset

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

	local function Callback(Event: Types.Process): boolean
		local Success, Error = pcall(DataStore.UpdateAsync, DataStore, Event.Key, function(Value: number | nil)
			if Event.Event == "Increment" then
				return (Value or 0) + Event.Value
			elseif Event.Event == "Set" then
				return if Order == "Highest"
					then math.max(Value or 0, Event.Value)
					else math.min(Value or 0, Event.Value)
			end
			return 0
		end)

		if not Success then
			warn(Error)
		end

		return Success
	end

	DataStore = DataStoreService:GetOrderedDataStore(if Cycle == "All-Time" then Name else `{Name}-{Cycle}:{Current}`)

	local self = setmetatable({
		_Cache = {} :: {},
		_Start = os.clock() - Refresh,
		_Order = Order,
		Updated = Signal.new(),
		Errored = Signal.new(),
		_Refresh = Refresh,
		_Interval = Interval,
		_DataStore = DataStore :: OrderedDataStore,
		_Processor = Processor.new(Callback, Config.BatchOverrides),
		_UTCOffset = UTCOffset,
		_DayOffset = DayOffset,
	}, ScoreSync)

	if Cycle ~= "All-Time" then
		RunService.Heartbeat:Connect(function()
			local Time = os.time() + DayOffset + UTCOffset
			local Key = math.floor(Time / Interval)

			if Key ~= Current then
				Current = Key
				DataStore = DataStoreService:GetOrderedDataStore(`{Name}-{Cycle}:{Current}`)

				self._Cache = {}
				self._DataStore = DataStore
			end

			if os.clock() - self._Start >= Refresh then
				self:GetOrderedListAsync() -- if it hasn't refreshed in a while, automatically refresh
			end
		end)
	end

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
	if not Amount then
		Amount = 1
	end

	local Index = Sift.Array.findWhere(self._Cache, function(Item)
		return Item.key == "User-" .. tostring(Player.UserId)
	end)

	if Index then
		self._Cache[Index].value += Amount
	else
		table.insert(self._Cache, {
			key = "User-" .. tostring(Player.UserId),
			value = Amount,
		})	
	end
	
	self.Updated:Fire(self._Cache)

	return Promise.resolve(self._Processor:Add({
		Time = os.time(),
		Event = "Increment",
		Value = Amount,
		Key = "User-" .. tostring(Player.UserId),
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
	local Index = Sift.Array.findWhere(self._Cache, function(Item)
		return Item.key == "User-" .. tostring(Player.UserId)
	end)

	if Index then
		local value = self._Cache[Index].value
		self._Cache[Index].value = if self._Order == "Highest"
			then math.max(Value or 0, value)
			else math.min(Value or 0, value)
	else
		table.insert(self._Cache, {
			key = "User-" .. tostring(Player.UserId),
			value = Value,
		})	
	end
	
	table.sort(self._Cache, function(A, B)
		return if self._Order == "Highest" then A.value > B.value else A.value < B.value
	end)

	self.Updated:Fire(self._Cache)

	return Promise.resolve(self._Processor:Add({
		Time = os.time(),
		Event = "Set",
		Value = Value,
		Key = "User-" .. tostring(Player.UserId),
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
    @return Promise<{ Result }>
]=]
function ScoreSync:GetOrderedListAsync(Count: number?, Min: number?, Max: number?): { { key: string, value: number } }
	local CanRefresh = os.time() - self._Start >= self._Refresh

	if not CanRefresh and not Min and not Max then
		return Promise.resolve(Array.filter(self._Cache, function(_, Index)
			return Index <= (Count or 100)
		end))
	end

	if CheckRequestBudget("Get") then
		self._Start = os.time()
		local _Success, Pages =
			pcall(self._DataStore.GetSortedAsync, self._DataStore, not self._Order, Count or 100, Min, Max)

		local List = {}

		if _Success and Pages and typeof(Pages) ~= "string" then
			local CurrentPage = Pages:GetCurrentPage()
			List = table.clone(CurrentPage)

			if not Min and not Max and not Array.equalsDeep(List, self._Cache) then -- only update cache when no value range is defined and the list is different
				self._Cache = List
				self.Updated:Fire(self._Cache)
			end
		end

		return Promise.resolve(List)
	end

	self.Errored:Fire("Request budget exceeded.")
	return Promise.reject("Request budget exceeded.")
end

return ScoreSync
