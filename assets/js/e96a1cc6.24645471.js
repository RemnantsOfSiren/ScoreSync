"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[294],{76132:e=>{e.exports=JSON.parse('{"functions":[{"name":"new","desc":"Creates a new ScoreSync object.\\n- `Name` (string): The name of the leaderboard.\\n- `UTC` (number, optional): The UTC offset for the leaderboard.\\n- `Type` (string, optional): The type of leaderboard (Highest or Lowest).\\n- `Cycle` (string, optional): The cycle of the leaderboard (All-Time, Yearly, Quarterly, Monthly, Weekly, Daily, Hourly).\\n- `Refresh` (number, optional): The refresh rate of the leaderboard.\\n- `BatchOverrides` (table, optional): The batch overrides for the leaderboard.\\n    - `Size` (number, optional): The number of requests to process at once. Defaults to 20\\n    - `Delay` (number, optional): The delay between each batch. Defaults to 30","params":[{"name":"Config","desc":"","lua_type":"{ Name: string, UTC: number?, Type: (\\"Highest\\" | \\"Lowest\\")?, Cycle: (\\"All-Time\\" | \\"Yearly\\" | \\"Quarterly\\" | \\"Monthly\\" | \\"Daily\\" | \\"Hourly\\")?, Refresh: number?, BatchOverrides: { Size: number?, Delay: number? }? }"}],"returns":[{"desc":"","lua_type":"ScoreSync"}],"function_type":"static","source":{"line":49,"path":"src/init.luau"}},{"name":"TimeUntilReset","desc":"","params":[{"name":"AsString","desc":"","lua_type":"boolean?"}],"returns":[{"desc":"","lua_type":"number | string"}],"function_type":"method","source":{"line":146,"path":"src/init.luau"}},{"name":"IncrementAsync","desc":"","params":[{"name":"Player","desc":"","lua_type":"Player"},{"name":"Amount","desc":"","lua_type":"number?"}],"returns":[{"desc":"","lua_type":"Promise<boolean>"}],"function_type":"method","source":{"line":165,"path":"src/init.luau"}},{"name":"SetAsync","desc":"","params":[{"name":"Player","desc":"","lua_type":"Player"},{"name":"Amount","desc":"","lua_type":"number"}],"returns":[{"desc":"","lua_type":"Promise<boolean>"}],"function_type":"method","source":{"line":185,"path":"src/init.luau"}},{"name":"GetOrderedListAsync","desc":"","params":[{"name":"Count","desc":"","lua_type":"number?"},{"name":"Min","desc":"","lua_type":"number?"},{"name":"Max","desc":"","lua_type":"number?"}],"returns":[{"desc":"","lua_type":"Promise<{ Result }>"}],"function_type":"method","source":{"line":209,"path":"src/init.luau"}}],"properties":[{"name":"Updated","desc":"","lua_type":"Signal","source":{"line":32,"path":"src/init.luau"}}],"types":[{"name":"Result","desc":"An object containing the key and value of a score.","lua_type":"(key: string, value: number)","source":{"line":200,"path":"src/init.luau"}}],"name":"ScoreSync","desc":"Leaderboard object (ScoreSync) for managing player scores.","source":{"line":54,"path":"src/init.luau"}}')}}]);