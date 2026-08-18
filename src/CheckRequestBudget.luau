--!strict
--!optimize 2
local DataStoreService = game:GetService("DataStoreService")

return function(Event: "Get" | "Set"): boolean
	local Success, BudgetOrError = pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService,
		if Event == "Get" then Enum.DataStoreRequestType.GetSortedAsync else Enum.DataStoreRequestType.UpdateAsync
	)

	if not Success then
		return false
	end

	local Budget = if type(BudgetOrError) == "number" then BudgetOrError else 0
	return Budget >= 15
end
