local DataStoreService = game:GetService("DataStoreService")

return function (Event: "Get" | "Set" | "Increment"): boolean
    local Budget
    local Success, Error = pcall(function() 
        Budget = DataStoreService:GetRequestBudgetForRequestType(if Event == "Get" then Enum.DataStoreRequestType.GetSortedAsync else Enum.DataStoreRequestType.SetIncrementSortedAsync)
    end)
    if not Success then
        warn(Error)
    end
    return (Budget or 0) > 0
end