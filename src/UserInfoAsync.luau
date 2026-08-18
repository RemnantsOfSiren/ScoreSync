--!strict
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
}

local Array = Sift.Array

local CachedUserInfo: { [number]: CachedInfo } = {}

local FLUSH_INTERVAL = 15

task.spawn(function()
    while task.wait(FLUSH_INTERVAL * 60) do
        table.clear(CachedUserInfo)
    end
end)

return function(Info: { Page }): { Types.Entry }
    local Users: { number } = Array.filter(Array.map(Info, function(Entry: Page)
        return tonumber(Entry.key)
    end), function(UserId: number)
        return CachedUserInfo[UserId] == nil
    end)

    if #Users > 0 then
        local Success, Results = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, Users)

        if Success then
            for _, Result in Results do
                CachedUserInfo[Result.Id] = {
                    Id = Result.Id,
                    Name = Result.DisplayName,
                    Verified = Result.HasVerifiedBadge,
                }
            end
        end
    end

    return Array.map(Info, function(Entry: Page): Types.Entry?
        local UserId = tonumber(Entry.key)

        if not UserId then
            return nil
        end

        local Cached = CachedUserInfo[UserId]

        if not Cached then
            return nil
        end

        return {
            Id = Cached.Id,
            Name = Cached.Name,
            Verified = Cached.Verified,
            Value = Entry.value,
        }
    end)
end
