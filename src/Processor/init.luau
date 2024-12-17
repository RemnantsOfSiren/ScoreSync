--!strict
local Queue = require(script.Queue)
local Types = require(script.Parent.Types)

local CheckRequestBudget = require(script.Parent.CheckRequestBudget)

local Processor = {}
Processor.__index = Processor

function Processor.new(Callback: (Event: Types.Process) -> boolean)
    local self = setmetatable({
        _Queue = Queue.new(),
    }, Processor)

    local Thread = task.spawn(function() 
        while true do
            local Next = self._Queue:Peek()
            
            if Next and CheckRequestBudget(Next.Event) and CheckRequestBudget("Get") then
                local Success = Callback(Next)

                if Success then
                    self._Queue:Remove(Next)
                end
            end

            task.wait(1)
        end
    end)

    game:BindToClose(function()
        if Thread then
            task.cancel(Thread)
            Thread = nil
        end
    end)
    
    return self
end

function Processor:Add(Process: Types.Process)
    self._Queue:Enqueue(Process)
end


return Processor