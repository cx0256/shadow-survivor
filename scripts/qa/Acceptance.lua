require "main"
DungeonApp.onReady=function()
    DungeonApp.testing=true
    local passed=require "qa/Simulation"
    print("[DungeonTests] "..passed.." simulation checks passed")
end
