local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScoreSync = require(ReplicatedStorage.Packages.ScoreSync)

local Score = ScoreSync.new({
    Name = "Score",
    Cycle = "Hourly",
    Refresh = 60,
})

local Player

repeat
    Player = Players:GetPlayers()[1]
    task.wait(1)
until Player

while task.wait() do
    Score:IncrementAsync(Player, 1)
    Score:GetOrderedListAsync():andThen(print)
end