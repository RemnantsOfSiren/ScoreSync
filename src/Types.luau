export type Process = {
	Key: string,
	Time: number,
	Value: number,
	Event: "Increment" | "Set",
}

export type Config = {
	UTC: number?,
	Name: string,
	Type: ("Highest" | "Lowest")?,
	Cycle: ("All-Time" | "Yearly" | "Quarterly" | "Monthly" | "Daily" | "Hourly")?,
	CycleDay: ("Sunday" | "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday")?,
	Refresh: number?,
	Version: number?,
	BatchOverrides: {
		Size: number?,
		Delay: number?,
	}?,
}

return {}
