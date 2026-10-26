-- Same ordinary-input comparison across every starter. Each run owns its RNG,
-- game and economy; no win requirement or artificial player invulnerability.
require "qa/Engagement"
---@type fun()
local compare=DungeonApp.onReady
DungeonApp.onReady=function()
    for starter=1,3 do
        rawset(_G,"DungeonEngagementConfig",{starter=starter,seeds={20261023,20261024}})
        compare()
    end
    rawset(_G,"DungeonEngagementConfig",nil)
    print("[EngagementVariants] 18 runs across three starters completed")
end
