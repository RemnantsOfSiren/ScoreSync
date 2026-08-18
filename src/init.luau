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
    _Fetching: boolean,
    _Destroyed: boolean,
}, Sync))

local MOCK_ID = HttpService:GenerateGUID(false)

local MAX_BACKOFF = 60
local WARN_AFTER = 10
local CLOSE_TIMEOUT = 25

-- Past 2^53 a Luau number can no longer represent consecutive integers, and the
-- value is outside what an OrderedDataStore will accept. Rejecting here is the only
-- place a bad value can be refused without losing it: the caller gets `false` back.
local MAX_VALUE = 2 ^ 53

local function GetMockKey(Name: string, Version: number)
    return `[ScoreSync]{Name}:{MOCK_ID}:{Version}`
end

type Process = {
    Key: string,
    Time: number,
    Sync: Sync,
    Store: OrderedDataStore,
    Order: "Highest" | "Lowest",
    Event: "Increment" | "Set",
    Value: number,
    Attempts: number,
    NextAttempt: number,
    Active: boolean,
}

local Queue: { Process } = {}

local function IsStorable(Value: number): boolean
    return type(Value) == "number" and math.abs(Value) <= MAX_VALUE
end

function Sync.Destroy(self: Sync)
    if self._Destroyed then
        return
    end

    self._Destroyed = true

    if self._Thread and coroutine.status(self._Thread) ~= "dead" then
        task.cancel(self._Thread)
    end

    self._Thread = nil
    self.Store = nil

    self.Updated:Destroy()

    table.clear(self._Cache)
end

function Sync._IncrementAsync(self: Sync, UserId: number, Value: number)
    local Store = self.Store

    if not Store then
        return false
    end

    if not IsStorable(Value) then
        warn(`[ScoreSync] Rejecting unstorable increment ({Value}) for {UserId}`)
        return false
    end

    for _, Process in Queue do
        if
            not Process.Active
            and rawequal(Process.Sync, self)
            and rawequal(Process.Store, Store)
            and Process.Key == tostring(UserId)
            and Process.Event == "Increment"
        then
            Process.Value += Value
            return true
        end
    end

    table.insert(Queue, {
        Key = tostring(UserId),
        Time = tick(),
        Sync = self,
        Store = Store,
        Order = self.Order,
        Event = "Increment",
        Value = Value,
        Attempts = 0,
        NextAttempt = 0,
        Active = false,
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
    local Store = self.Store

    if not Store then
        return false
    end

    if not IsStorable(Value) then
        warn(`[ScoreSync] Rejecting unstorable value ({Value}) for {UserId}`)
        return false
    end

    for _, Process in Queue do
        if
            not Process.Active
            and rawequal(Process.Sync, self)
            and rawequal(Process.Store, Store)
            and Process.Key == tostring(UserId)
            and Process.Event == "Set"
        then
            Process.Value = Value
            return true
        end
    end

    table.insert(Queue, {
        Key = tostring(UserId),
        Time = tick(),
        Sync = self,
        Store = Store,
        Order = self.Order,
        Event = "Set",
        Value = Value,
        Attempts = 0,
        NextAttempt = 0,
        Active = false,
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
    if self._Destroyed or self._Fetching or tick() - self._Debounce < self._Refresh then
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

    self._Fetching = true

    local _Success, ListOrError = pcall(Store.GetSortedAsync, Store, self.Order ~= "Highest", Count or 100)

    if not (_Success and ListOrError and typeof(ListOrError) ~= "string") then
        self._Fetching = false

        if RunService:IsStudio() then
            warn("[ScoreSync] Error fetching ordered list: ", ListOrError)
        end

        return self._Cache
    end

    if self._Destroyed or not rawequal(self.Store, Store) then
        self._Fetching = false
        return self._Cache
    end

    local _InfoSuccess, EntriesOrError, Resolved = pcall(function()
        return UserInfoAsync(ListOrError:GetCurrentPage())
    end)

    self._Fetching = false
    self._Debounce = tick()

    if not _InfoSuccess then
        if RunService:IsStudio() then
            warn("[ScoreSync] Error resolving user info: ", EntriesOrError)
        end

        return self._Cache
    end

    if not Resolved and #self._Cache > 0 then
        if RunService:IsStudio() then
            warn("[ScoreSync] Page had unresolved users, keeping the previous list")
        end

        return self._Cache
    end

    self._Cache = EntriesOrError :: { Types.Entry }

    self.Updated:Fire(self._Cache)
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
                _Fetching = false,
                _Destroyed = false,
            }, Sync)
        end,
    })
end

local Closing = false
local CurrentProcess: Process? = nil

local function Transform(OldValue: number?): number
    local Process = CurrentProcess :: Process
    local Value = math.floor(Process.Value)

    if Process.Event == "Increment" then
        return math.floor(OldValue or 0) + Value
    end

    if not OldValue then
        return Value
    end

    return if Process.Order == "Highest"
        then math.max(math.floor(OldValue), Value)
        else math.min(math.floor(OldValue), Value)
end

local Processor = task.spawn(function()
    while task.wait(if Closing then 0.05 else 1) do
        if #Queue == 0 or not CheckRequestBudget("Set") then
            continue
        end

        table.sort(Queue, function(A, B)
            return A.Time < B.Time
        end)

        local Now = tick()
        local Next = nil

        for Index, Queued in Queue do
            if Closing or Queued.NextAttempt <= Now then
                Next = Index
                break
            end
        end

        if not Next then
            continue
        end

        local Process = Queue[Next]
        local Store = Process.Store

        CurrentProcess = Process
        Process.Active = true

        local _Success, ResultOrError, _KeyInfo = pcall(Store.UpdateAsync, Store, Process.Key, Transform)

        Process.Active = false
        CurrentProcess = nil

        if _Success then
            local Index = table.find(Queue, Process)

            if Index then
                table.remove(Queue, Index)
            end
        else
            Process.Attempts += 1
            Process.NextAttempt = tick() + math.min(2 ^ Process.Attempts, MAX_BACKOFF)

            if RunService:IsStudio() or Process.Attempts == WARN_AFTER then
                warn(`[ScoreSync] Failed to update {Process.Key} (attempt {Process.Attempts}), still retrying: `, ResultOrError)
            end
        end
    end
end)

game:BindToClose(function()
    Closing = true

    local Deadline = tick() + CLOSE_TIMEOUT

    while #Queue > 0 and tick() < Deadline do
        task.wait(.1)
    end

    if #Queue > 0 then
        warn(`[ScoreSync] Shutting down with {#Queue} unsaved entries remaining.`)
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

    if Cycle ~= "All-Time" then
        Current = math.floor((DateTime.now().UnixTimestamp + DayOffset + UTCOffset) / Interval)
    end

    local self = setmetatable({
        Name = `{Config.Name}:{Cycle}:{Version}`,
        Order = Order,
        Store = DataStoreService:GetOrderedDataStore(Key, if Cycle == "All-Time" then "All-Time" else `{Cycle}:{Current}`),
        Version = Version,
        Updated = Signal.new(),
        TimeRemaining = Interval,

        _Cache = {},
        _Config = Config,
        _Refresh = Refresh,
        _Debounce = tick() - Refresh,
        _Fetching = false,
        _Destroyed = false,
    }, Sync)

    self._Thread = task.spawn(function()
        while task.wait(1) do
            if Cycle ~= "All-Time" then
                local DTime = DateTime.now().UnixTimestamp + DayOffset + UTCOffset
                local NextInterval = math.floor(DTime / Interval)

                if NextInterval ~= Current then
                    Current = NextInterval
                    self._Cache = {}
                    self._Debounce = tick() - self._Refresh
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
