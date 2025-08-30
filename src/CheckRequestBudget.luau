local DataStoreService = game:GetService("DataStoreService")

return function(Event: "Get" | "Set" | "Increment", Batch: number?): boolean
	local Budget
	local Success = pcall(function()
		Budget = DataStoreService:GetRequestBudgetForRequestType(
			if Event == "Get"
				then Enum.DataStoreRequestType.GetSortedAsync
				else Enum.DataStoreRequestType.SetIncrementSortedAsync
		)
	end)
	return if Success then (Budget or 0) >= (Batch or 20) else false
end
