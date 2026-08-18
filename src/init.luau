--!strict
--!optimize 2
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local Types = require(script.Types)
local Signal = require(script.Parent.Signal)

local UserInfoAsync = require(script.UserInfoAsync)
local CheckRequestBudget = require(script.CheckRequestBudget)

local Success = pcall(function() 
    local Store = DataStoreService:GetDataStore("ScoreSync")
    Store:SetAsync("Enabled", true)
end)

local Sync = {}
Sync.__index = Sync

export type Entry = Types.Entry
export type Config = Types.Config

export type Sync = typeof(setmetatable({} :: {
    Name: string,
    Store: OrderedDataStore?,
    Order: "Highest" | "Lowest",
    Version: number,
    Updated: typeof(Signal.new()),
    TimeRemaining: number,

    _Cache: { Types.Entry },
    _Config: Types.Config,
    _Thread: thread?,
    _Refresh: number,
    _Debounce: number,
}, Sync))

local MOCK_ID = HttpService:GenerateGUID(false)

local function GetMockKey(Name: string, Version: number)
    return `[ScoreSync]{Name}:{MOCK_ID}:{Version}`
end

type Process = {
    Key: string,
    Time: number,
    Sync: Sync,
    Event: "Increment" | "Set",
    Value: number,
}

local Queue: { Process } = {}

function Sync.Destroy(self: Sync)
    table.clear(self :: any)
end

function Sync._IncrementAsync(self: Sync, UserId: number, Value: number)
    local Time = tick()

    for _, Process in Queue do
        if rawequal(Process.Sync, self) and Time > Process.Time and Process.Key == tostring(UserId) and Process.Event == "Increment" then
            Process.Time = Time
            Process.Value += Value
            return true
        end
    end
    
    table.insert(Queue, {
        Key = tostring(UserId),
        Time = Time,
        Sync = self,
        Event = "Increment",
        Value = Value,
    })

    return true
end

function Sync.IncrementAsync(self: Sync, Player: Player, Value: number)
    if not self.Store then
        if RunService:IsStudio() then
            warn("[ScoreSync] Attempting to increment before the store is initialized")
        end
        
        return false
    end
    
    if self._Config.Predicate and not self._Config.Predicate(Player) then
        if RunService:IsStudio() then
            warn("[ScoreSync] Player does not meet criteria!")
        end

        return false
    end

    return self:_IncrementAsync(Player.UserId, Value)
end

function Sync._SetAsync(self: Sync, UserId: number, Value: number)
    local Time = tick()
    for _, Process in Queue do
        if rawequal(Process.Sync, self) and Time > Process.Time and Process.Key == tostring(UserId) and Process.Event == "Set" then
            Process.Time = Time
            Process.Value = Value
            return true
        end
    end
    
    table.insert(Queue, {
        Key = tostring(UserId),
        Time = Time,
        Sync = self,
        Event = "Set",
        Value = Value,
    })
    return true
end

function Sync.SetAsync(self: Sync, Player: Player, Value: number)
    if not self.Store then
        if RunService:IsStudio() then
            warn("[ScoreSync] Attempting to set before the store is initialized")
        end
        return false
    end

    if self._Config.Predicate and not self._Config.Predicate(Player) then
        if RunService:IsStudio() then
            warn("[ScoreSync] Player does not meet criteria!")
        end
        return false
    end

    return self:_SetAsync(Player.UserId, Value)
end

function Sync.GetOrderedList(self: Sync, Count: number?)
    if tick() - self._Debounce < self._Refresh then
        return self._Cache
    end

    local Store = self.Store
    
    if not Store then
        if RunService:IsStudio() then
            warn("[ScoreSync] Attempting to get ordered list before the store is initialized")
        end

        return self._Cache
    end

    if not CheckRequestBudget("Get") then
        if RunService:IsStudio() then
            warn("[ScoreSync] Request budget exceeded!")
        end

        return self._Cache
    end

    local _Success, ListOrError = pcall(Store.GetSortedAsync, Store, self.Order ~= "Highest", Count or 100)

    if _Success and ListOrError and typeof(ListOrError) ~= "string" then
        self._Debounce = tick()
        
        self._Cache = UserInfoAsync(ListOrError:GetCurrentPage())
        
        self.Updated:Fire(self._Cache)
        return self._Cache
    end

    return self._Cache
end

if not Success then
    return table.freeze({
        new = function(Config: Types.Config): Sync
            warn("[ScoreSync] API Access is disabled, please enable it in Game Settings.")

            local Order: "Highest" | "Lowest" = Config.Type or "Highest"

            return setmetatable({
                Name = `{Config.Name}:{Config.Cycle or "All-Time"}:{Config.Version or 1}`,
                Order = Order,
                Version = Config.Version or 1,
                Updated = Signal.new(),
                TimeRemaining = math.huge,

                _Cache = {},
                _Config = Config,
                _Refresh = math.huge,
                _Debounce = tick(),
            }, Sync)
        end,
    })
end

local CurrentProcess: Process? = nil

local function Transform(OldValue: number?): number
    local Process = CurrentProcess :: Process
    local Value = Process.Value

    return if Process.Event == "Increment" then math.floor((OldValue or 0) + Value)
        else if Process.Sync.Order == "Highest"
        then if not OldValue then math.floor(Value) else math.max(math.floor(OldValue), math.floor(Value))
    else if not OldValue then math.floor(Value) else math.min(math.floor(OldValue), math.floor(Value))
end

local Processor = task.spawn(function()
    while task.wait(1) do
        if #Queue > 0 and CheckRequestBudget("Set") then
            table.sort(Queue, function(A, B)
                return A.Time < B.Time
            end)

            local Process = Queue[1]
            if Process then
                local Store = Process.Sync.Store

                if not Store then
                    table.remove(Queue, 1)
                    continue
                end

                CurrentProcess = Process

                local _Success, ResultOrError, _KeyInfo = pcall(Store.UpdateAsync, Store, Process.Key, Transform)

                if _Success then
                    table.remove(Queue, 1)
                else
                    if RunService:IsStudio() then
                        warn("[ScoreSync] Error updating store: ", ResultOrError)
                    end
                end
            end
        end
    end
end)

game:BindToClose(function()
    while #Queue > 0 do
        task.wait(.1)
    end

    if Processor and coroutine.status(Processor) ~= "dead" then
        task.cancel(Processor)
    end
end)

local DayToNumberLookup = {
	Sunday = 3,
	Monday = 2,
	Tuesday = 1,
	Wednesday = 0,
	Thursday = -1,
	Friday = -2,
	Saturday = -3,
}

local function BuildSync(Config: Types.Config): Sync
    local Order: "Highest" | "Lowest" = Config.Type or "Highest"
    local Refresh = Config.Refresh or 120
    local Version = Config.Version or 1
    local UTCOffset = if Config.UTC then Config.UTC * 3600 else 0

    local Cycle = Config.Cycle or "All-Time"
    local Current: number? = nil
    local Interval = math.huge
    local DayOffset = DayToNumberLookup[Config.CycleDay or "Friday"] * 86400
        
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

    local Key = `[ScoreSync]{Config.Name}:{Version}`
    
    if Config.Mock then
        Key = GetMockKey(Config.Name, Version)
    end

    local self = setmetatable({
        Name = `{Config.Name}:{Cycle}:{Version}`,
        Order = Order,
        Store = DataStoreService:GetOrderedDataStore(Key, Cycle == "All-Time" and "All-Time" or `{Cycle}:{Current}`),
        Version = Version,
        Updated = Signal.new(),
        TimeRemaining = Interval,

        _Cache = {},
        _Config = Config,
        _Refresh = Refresh,
        _Debounce = tick() - Refresh,
    }, Sync)

    self._Thread = task.spawn(function()
        while task.wait(1) do
            if Config.Cycle ~= "All-Time" then
                local DTime = DateTime.now().UnixTimestamp + DayOffset + UTCOffset
                local NextInterval = math.floor(DTime / Interval)
                
                if NextInterval ~= Current then
                    Current = NextInterval
                    self._Cache = {}
                    self.Store = DataStoreService:GetOrderedDataStore(Key, `{Cycle}:{Current}`)
                end

                self.TimeRemaining = Interval - math.floor(DTime % Interval)
            end

            self:GetOrderedList()
        end
    end)

    return self :: Sync
end

return table.freeze({
    new = BuildSync,
})