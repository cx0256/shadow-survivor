require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type {Roles: table[], Apply: fun(g: table), Merge: fun(g: table, index: number): boolean}
local Builds=require "Builds"
---@type SurvivorRulesAPI
local Survival=require "Survival"
DungeonApp.onReady=function()
    DungeonApp.testing=true
    local checks=0
    local function check(ok,msg) assert(ok,msg) checks=checks+1 end
    for i=1,4 do
        local g=Dungeon.New({}) g.role=i g:Start()
        check(g.role==i and g.player.hp==g.player.maxHp,"role survives start and restores HP")
        local sword=g:WeaponStats({kind=1,tier=1}).damage
        check(math.abs(sword-20*Builds.Roles[i].damage[1])<0.001,"role damage applies to weapon")
    end
    local g=Dungeon.New({}) g:Start() g.state="shop" g.waveActive=false g.autoFuse=false
    check(Survival.AddWeapon(g,1,1) and #g.loadout==2,"expansion adds matching weapon without fusion")
    check(Builds.Merge(g,1) and #g.loadout==1 and g.loadout[1].tier==2,"manual fusion upgrades and frees slot")
    check(not Builds.Merge(g,1),"unmatched fusion is safe")
    g.state="playing"
    check(not Builds.Merge(g,1),"cannot fuse during combat")
    print("[BuildTests] "..checks.." checks passed")
end
