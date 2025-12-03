local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

return function(Event: "Get" | "Set" | "Increment", Batch: number?): boolean
	local Budget
	local Success = pcall(function()
		Budget = DataStoreService:GetRequestBudgetForRequestType(
			if Event == "Get"
				then Enum.DataStoreRequestType.GetSortedAsync
				else Enum.DataStoreRequestType.UpdateAsync
		)
	end)
	local Offset = (Batch or 20) + (Players.MaxPlayers * 3) -- 2 requests per player for other libraries
	return if Success then (Budget or 0) >= Offset else false
end
