require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
DungeonApp.onReady=function()
    DungeonApp.testing=true
    local g=Dungeon.New({}) g:Start()
    local e=g:SpawnEnemy("skeleton",g.player.x+65,g.player.y,false)
    e.born=-0.25
    g:Update(0.02,0,0)
    assert(not e.dead and e.hp==e.maxHp and g.loadout[1].cd==0,
        "sword must not attack invisible enemies during spawn warning")
    print("[SwordRegression] spawn-warning check passed")
end
