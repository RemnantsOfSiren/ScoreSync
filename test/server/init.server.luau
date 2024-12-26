local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScoreSync = require(ReplicatedStorage.Packages.ScoreSync)

local Player

repeat
    Player = Players:GetPlayers()[1]
    task.wait(1)
until Player

for _, Cycle in {"Hourly", "Weekly"} do 
    local Score = ScoreSync.new({
        Name = "Score",
        Cycle = Cycle,
        CycleDay = "Tuesday",
        Refresh = 60,
    })

    Score.Updated:Connect(print)

    task.spawn(function()
        while task.wait(1) do
            Score:IncrementAsync(Player, 1)
            print(Score:TimeUntilReset(true))
        end
    end)
end