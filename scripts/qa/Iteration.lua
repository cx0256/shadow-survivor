-- Combine real input callbacks, combat regressions, new rules, and Yoga layout
-- in one native headless invocation. No desktop input or preview window.
require "qa/Interface"
---@type fun()
local interface=DungeonApp.onReady
require "qa/Sword"
---@type fun()
local sword=DungeonApp.onReady
require "qa/EngagementRules"
---@type fun()
local rules=DungeonApp.onReady
require "qa/RecipeEvolutions"
---@type fun()
local recipes=DungeonApp.onReady
require "qa/InterfaceStyle"
---@type fun()
local layout=DungeonApp.onReady
DungeonApp.onReady=function()
    interface() sword() rules() recipes() layout()
    print("[IterationChecks] input, combat, engagement rules and native layouts completed")
end
