--!strict
--!optimize 2
export type Entry = {
	Id: number,
	Rank: number,
	Name: string,
	Value: number,
	Verified: boolean,
}

export type Config = {
	UTC: number?,
	Name: string,
	Type: ("Highest" | "Lowest")?,
	Mock: boolean?,
	Cycle: ("All-Time" | "Yearly" | "Quarterly" | "Monthly" | "Weekly" | "Daily" | "Hourly")?,
	Refresh: number?,
	Version: number?,
	CycleDay: ("Sunday" | "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday")?,
	Predicate: ((Player: Player) -> boolean)?,
	BatchOverrides: {
		Size: number?,
		Delay: number?,
	}?,
	SavedRequestsPerPlayer: number?,
}

return {}
