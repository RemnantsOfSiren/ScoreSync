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
	Refresh: number?,
	BatchOverrides: {
		Size: number?,
		Delay: number?,
	}?,
}

return {}
