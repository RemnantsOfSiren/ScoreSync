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
    @param Config { Name: string, UTC: number?, Type: ("Highest" | "Lowest")?, Cycle: ("All-Time" | "Yearly" | "Quarterly" | "Monthly" | "Daily" | "Hourly")?, Refresh: number? }
    @return ScoreSync
]=]

--[=[
    @class ScoreSync
    Leaderboard object (ScoreSync) for managing player scores.
]=]
function ScoreSync.new(Config: Types.Config)
    local Name = if RunService:IsStudio() then "Mock" .. Config.Name else Config.Name
    local Refresh = Config.Refresh or 60
    local UTCOffset = if Config.UTC then Config.UTC * 3600 else 0 

    local Cycle = Config.Cycle or "All-Time"
    local Current = nil
    local Interval = math.huge
    local DataStore = nil

    if Cycle ~= "All-Time" then
        local Time = os.clock() + UTCOffset

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
                return Event.Value
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
        _Cache = {},
        _Refresh = Refresh,
        _DataStore = DataStore,
        _Processor = Processor.new(Callback),
        _Order = Config.Type == nil or Config.Type == "Highest",
        _Start = os.clock() - Refresh,
        Updated = Signal.new(),
    }, ScoreSync)

    if Cycle ~= "All-Time" then
        RunService.Heartbeat:Connect(function()
            local Time = os.clock() + UTCOffset
            local Key = math.floor(Time / Interval)

            if Key ~= Current then
                Current = Key
                DataStore = DataStoreService:GetOrderedDataStore(`{Name}-{Cycle}:{Current}`)
                
                self._Cache = {}
                self._DataStore = DataStore
            end
        end)
    end

    return self
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

    return Promise.resolve(self._Processor:Add({
        Time = os.clock(),
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
    return Promise.resolve(self._Processor:Add({
        Time = os.clock(),
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
function ScoreSync:GetOrderedListAsync(Count: number?, Min: number?, Max: number?): {{ key: string, value: number }}
    local CanRefresh = os.clock() - self._Start >= self._Refresh
    
    if not CanRefresh and not Min and not Max then
        return Promise.resolve(Array.filter(self._Cache, function(_, Index) 
            return Index <= (Count or 100)
        end))
    end

    if CheckRequestBudget("Get") then
        self._Start = os.clock()
        local _Success, Pages = pcall(self._DataStore.GetSortedAsync, self._DataStore, not self._Order, Count or 100, Min, Max)

        local List = {}

        if _Success and Pages and typeof(Pages) ~= "string" then
            local CurrentPage = Pages:GetCurrentPage()
            List = table.clone(CurrentPage)

            if not Min and not Max then -- only update cache when no value range is defined
                self._Cache = List
            end
        end

        return Promise.resolve(List)
    end

    return Promise.reject("Request budget exceeded.")
end

return ScoreSync