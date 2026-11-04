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
local ProgressSave=require "ProgressSave"

local function checkProgressSave()
    local path="qa-shadow-progress-"..os.time()..".json"
    local function writeFixture(destination,value)
        local file=File(destination,FILE_WRITE)
        assert(file and file:IsOpen(),"native save fixture opens")
        assert(file:WriteString(value),"native save fixture writes")
        file:Close()
    end
    writeFixture(path,cjson.encode({runs=7,bestWave=3}))
    local saved,generation=ProgressSave.Load(path)
    assert(saved.runs==7 and generation==0,"native legacy progress loads")
    generation=assert(ProgressSave.Write(path,{runs=8,bestWave=3},generation))
    generation=assert(ProgressSave.Write(path,{runs=9,bestWave=4},generation))
    saved=ProgressSave.Load(path)
    assert(saved.runs==9 and saved.bestWave==4,"native reader selects the newest verified save")
    writeFixture(path.."."..(generation%2),"{\"generation\":2,")
    saved,generation=ProgressSave.Load(path)
    assert(saved.runs==8 and generation==1,"native reader recovers from an interrupted write")
    for _,suffix in ipairs({"",".0",".1"}) do fileSystem:Delete(path..suffix) end
    print("[ProgressSaveChecks] native legacy, alternating slots and corrupt slot recovery passed")
end

DungeonApp.onReady=function()
    interface() sword() rules() recipes() layout()
    checkProgressSave()
    print("[IterationChecks] input, combat, engagement rules and native layouts completed")
end
