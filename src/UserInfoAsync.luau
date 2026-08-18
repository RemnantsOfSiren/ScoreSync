--!strict
--!optimize 2
local UserService = game:GetService("UserService")

local Types = require(script.Parent.Types)
local Sift = require(script.Parent.Parent.Sift)

export type Page = {
    key: string,
    value: number,
}

type CachedInfo = {
    Id: number,
    Name: string,
    Verified: boolean,
    Expires: number,
}

local Array = Sift.Array

local CachedUserInfo: { [number]: CachedInfo } = {}

local TTL = 15 * 60
local BATCH_SIZE = 100
local SWEEP_INTERVAL = 60
local UNRESOLVED_TTL = 5 * 60

task.spawn(function()
    while task.wait(SWEEP_INTERVAL) do
        local Now = os.clock()

        for UserId, Cached in CachedUserInfo do
            if Now - Cached.Expires > TTL then
                CachedUserInfo[UserId] = nil
            end
        end
    end
end)

return function(Info: { Page }): ({ Types.Entry }, boolean)
    local Now = os.clock()

    local Stale: { number } = Array.filter(Array.map(Info, function(Entry: Page)
        return tonumber(Entry.key)
    end), function(UserId: number)
        local Cached = CachedUserInfo[UserId]
        return Cached == nil or Now > Cached.Expires
    end)

    for Index = 1, #Stale, BATCH_SIZE do
        local Batch = table.move(Stale, Index, math.min(Index + BATCH_SIZE - 1, #Stale), 1, {})

        local Success, Results = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, Batch)

        if not Success then
            continue
        end

        for _, Result in Results do
            CachedUserInfo[Result.Id] = {
                Id = Result.Id,
                Name = Result.DisplayName,
                Verified = Result.HasVerifiedBadge,
                Expires = Now + TTL,
            }
        end

        for _, UserId in Batch do
            local Cached = CachedUserInfo[UserId]

            if not Cached then
                CachedUserInfo[UserId] = {
                    Id = UserId,
                    Name = `Player {UserId}`,
                    Verified = false,
                    Expires = Now + UNRESOLVED_TTL,
                }
            elseif Cached.Expires <= Now then
                Cached.Expires = Now + UNRESOLVED_TTL
            end
        end
    end

    local Entries: { Types.Entry } = {}
    local Resolved = true

    for _, Entry in Info do
        local UserId = tonumber(Entry.key)

        if not UserId then
            continue
        end

        local Cached = CachedUserInfo[UserId]

        if not Cached then
            Resolved = false
        end

        table.insert(Entries, {
            Id = UserId,
            Rank = #Entries + 1,
            Name = if Cached then Cached.Name else `Player {UserId}`,
            Verified = if Cached then Cached.Verified else false,
            Value = Entry.value,
        })
    end

    return Entries, Resolved
end
