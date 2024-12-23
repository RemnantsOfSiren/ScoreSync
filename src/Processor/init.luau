--!strict
local Queue = require(script.Queue)
local Types = require(script.Parent.Types)

local CheckRequestBudget = require(script.Parent.CheckRequestBudget)

--[=[
    @class Processor
    Processor object for managing the processing of events.
]=]
local Processor = {}
Processor.__index = Processor

--[=[
    @function new
    @within Processor
    @param Callback (Event: Types.Process) -> boolean
    @param Config { Size: number?, Delay: number? }?
    @return Processor

    Creates a new Processor object.
    - `Callback` ((Event: Types.Process) -> boolean): The callback function to process the events.
    - `Config` (table, optional): The configuration for the Processor.
        - `Size` (number, optional): The number of requests to process at once. Defaults to 20
        - `Delay` (number, optional): The delay between each batch. Defaults to 30
    
    The Processor object processes events in a queue, in a batch like manor, with a delay between each batch.
    The Processor object will attempt to process all events in the queue, in the event of a server shutdown.
]=]
function Processor.new(Callback: (Event: Types.Process) -> boolean, Config: { Size: number?, Delay: number? }?)
	local self = setmetatable({
		_Queue = Queue.new(),
	}, Processor)

	local Thread = task.spawn(function()
		while true do
			if self._Queue:Size() > 0 then
				local BatchSize = Config and Config.Size or 20

				for _ = BatchSize, 1, -1 do
					local Process = self._Queue:Peek()

					if not Process then
						break
					end

					if not CheckRequestBudget("Get", BatchSize) then
						break
					end

					if not CheckRequestBudget(Process.Event, BatchSize) then
						break
					end

					if Callback(Process) then
						self._Queue:Remove(Process)
					end
				end

				task.wait(Config and Config.Delay or 30)
			end

			task.wait()
		end
	end)

	game:BindToClose(function()
		if Thread and coroutine.status(Thread) ~= "dead" then
			task.cancel(Thread)
		end

        -- Process the remaining queue on server shutdown
        while self._Queue:Size() > 0 do
            local Process = self._Queue:Peek()

            if Process and CheckRequestBudget(Process.Event) and Callback(Process) then
                self._Queue:Remove(Process)
            end

            task.wait()
        end
	end)

	return self
end

function Processor:Add(Process: Types.Process)
	self._Queue:Enqueue(Process)
end

return Processor
