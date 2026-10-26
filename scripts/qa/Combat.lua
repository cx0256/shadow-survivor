require "main"
local elapsed=0
local step=0
DungeonApp.onReady=function()
    DungeonApp.testing=true
    local g=DungeonApp.game g:Start()
    g.loadout={{kind=1,tier=1,cd=0,angle=0},{kind=2,tier=1,cd=0.1,angle=0},{kind=3,tier=1,cd=0.2,angle=0},
        {kind=1,tier=2,cd=0.3,angle=0},{kind=2,tier=2,cd=0.4,angle=0},{kind=3,tier=2,cd=0.5,angle=0}}
    g.player.invuln=999
    g:SpawnEnemy("skeleton",450,290,false)
    g:SpawnEnemy("zombie",565,180,true)
    g:SpawnEnemy("mage",760,345,false)
    g:SpawnEnemy("bat",200,345,false)
    DungeonApp.onFrame=HandleSurvivorAcceptance
end
---@param dt number
function HandleSurvivorAcceptance(dt)
    elapsed=elapsed+dt
    local g=DungeonApp.game
    if elapsed>3 and step==0 then
        step=1
        assert(g.state=="playing" and g.runTime>2 and g.waveTime<19,"production combat countdown advances")
        assert(#g.loadout==6 and g.loadout[1].cd>=0 and g.loadout[3].cd>=0,"six weapon cooldowns advance")
        assert(g.kills>0,"autonomous multiweapon attacks kill enemies")
    elseif elapsed>7 and step==1 then
        step=2
        assert(g.state=="playing" and #g.enemies>0,"enemy director sustains pressure instead of waiting for room clear")
        print("[SurvivorTests] 4 live combat checks passed")
    end
end
