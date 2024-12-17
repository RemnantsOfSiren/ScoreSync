--!strict
local Sift = require(script.Parent.Parent.Parent.Sift)

local Types = require(script.Parent.Parent.Types)

local Array = Sift.Array

local Queue = {}
Queue.__index = Queue

function Queue.new()
    return setmetatable({
        List = {} :: {Types.Process},
    }, Queue)
end

function Queue:Enqueue(Process: Types.Process)
    local FindInQueue = Array.findWhere(self.List, function(_Queue: Types.Process)
        return _Queue.Key == Process.Key and _Queue.Event == Process.Event
    end)

    local Found: Types.Process = FindInQueue and self.List[FindInQueue]

    if Found then
        if Found.Event == "Set" and Found.Time < Process.Time then
            Found.Value = Process.Value
        elseif Found.Event == "Increment" then
            Found.Value += Process.Value
        end
    else
        table.insert(self.List, Process)
    end
    
    return true
end

function Queue:Dequeue()
    if #self.List == 0 then
        return nil
    end

    return table.remove(self.List, 1)
end

function Queue:Peek()
    return self.List[1]
end

function Queue:Clear()
    table.clear(self.List)
end

function Queue:Remove(Process: Types.Process)
    for I = #self.List, 1, -1 do
        if self.List[I] == Process then
            table.remove(self.List, I)
            return true
        end
    end
    return false
end

return Queue