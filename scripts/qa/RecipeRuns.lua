-- Same shopping economy and movement policy, choose recipe evolution or spend
-- the voucher on a free weapon instead. This compares routes, not a pure buff.
require "qa/Engagement"
---@type fun()
local compare=DungeonApp.onReady
DungeonApp.onReady=function()
    for starter=1,3 do
        for _,enabled in ipairs({false,true}) do
            rawset(_G,"DungeonEngagementConfig",{starter=starter,seeds={20261025},strategies={"adaptive"},recipes=enabled})
            compare()
        end
    end
    rawset(_G,"DungeonEngagementConfig",nil)
    print("[RecipeRunChecks] six ordinary-input recipe/free-weapon route comparisons completed")
end
