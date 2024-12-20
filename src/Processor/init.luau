--!strict
local Queue = require(script.Queue)
local Types = require(script.Parent.Types)

local CheckRequestBudget = require(script.Parent.CheckRequestBudget)

local Processor = {}
Processor.__index = Processor

function Processor.new(Callback: (Event: Types.Process) -> boolean, Config: { Size: number?, Delay: number?}?)
    local self = setmetatable({
        _Queue = Queue.new(),
    }, Processor)

    local Thread = task.spawn(function() 
        while true do
            if self._Queue:Size() > 0 then 
                local BatchSize = Config and Config.Size or 20

                for _ = BatchSize, 1, -1 do
                    local Process = self._Queue:Peek()

                    if not Process then break end

                    if not CheckRequestBudget("Get", BatchSize) then break end
                    if not CheckRequestBudget(Process.Event, BatchSize) then break end

                    if not Callback(Process) then
                        self._Queue:Enqueue(Process)
                    else
                        self._Queue:Remove(Process)
                    end
                end

                task.wait(Config and Config.Delay or 30)
            end

            task.wait()
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