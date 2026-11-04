-- Normal movement, skills and economy; the policy pursues visible map goals.
require "qa/Engagement"
local compare=DungeonApp.onReady
DungeonApp.onReady=function()
    for starter=1,3 do
        DungeonEngagementConfig={starter=starter,seeds={20261023,20261024},strategies={"raider"}}
        compare()
    end
    DungeonEngagementConfig=nil
    print("[ObjectiveRuns] six ordinary-input objective runs completed")
end
