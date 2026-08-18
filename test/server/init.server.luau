local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScoreSync = require(ReplicatedStorage.Packages.ScoreSync)

local Player

repeat
    Player = Players:GetPlayers()[1]
    task.wait(1)
until Player

for _, Cycle in {"Daily", "Weekly"} do 
    local Score = ScoreSync.new({
        Name = "Test Score",
        Cycle = Cycle,
        CycleDay = "Tuesday",
        Refresh = 60,
    })

    Score.Updated:Connect(function(List)
        print(`[Test Score] - Cycle: {Cycle}, List:`, List)
    end)

    task.spawn(function()
        while true do
            for I = 1, 10 do
                Score:_IncrementAsync(math.random(100000, 1000000), math.random(1, 40))
            end
            task.wait(1)
        end
    end)
end