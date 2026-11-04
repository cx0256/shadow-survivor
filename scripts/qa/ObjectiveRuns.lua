-- Normal movement, skills and economy; the policy pursues visible map goals.
require "qa/Engagement"
local compare=DungeonApp.onReady
DungeonApp.onReady=function()
    for starter=1,3 do
        DungeonEngagementConfig={starter=starter,seeds={20261023,20261024,20261025,20261104},strategies={"raider","stay"}}
        compare()
    end
    DungeonEngagementConfig=nil
    print("[ObjectiveRuns] 24 early-exit/stay comparisons completed")
end
