export type Entry = {
	Id: number,
	Name: string,
	Verified: boolean,
	Value: number,
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
