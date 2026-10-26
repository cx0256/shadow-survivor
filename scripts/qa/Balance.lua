-- Deterministic, ordinary-input bot: no invulnerability, injected money or
-- wave skipping. Its result is telemetry, not a human difficulty verdict.
require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
DungeonApp.onReady=function()
    DungeonApp.testing=true
    math.randomseed(20261022)
    local g=Dungeon.New({}) g:SetWeapon(rawget(_G,"DungeonBalanceStarter") or 2) g:Start()
    local frames=0
    while g.state~="dead" and g.state~="win" and frames<10000 do
        if g.state=="talent" then
            local choice=1
            for i,t in ipairs(g.choices) do if t.stat=="atk" or t.stat=="haste" then choice=i break end end
            g:ChooseTalent(choice)
        elseif g.state=="shop" then
            for i,offer in ipairs(g.shop) do
                if offer.type=="weapon" then g:BuyShop(i) end
            end
            for i=1,4 do g:BuyShop(i) end
            g:BeginWave()
        else
            local p=g.player
            local angle=g.runTime*0.6
            local tx,ty=480+math.cos(angle)*270,315+math.sin(angle)*125
            local dx,dy=tx-p.x,ty-p.y
            local len=math.max(1,math.sqrt(dx*dx+dy*dy))
            dx=dx/len dy=dy/len
            if g:HitsWall(p.x+dx*35,p.y+dy*35,p.r) then
                local turned=false
                for _,offset in ipairs({0.7,-0.7,1.4,-1.4,2.1,-2.1}) do
                    local a=math.atan(dy,dx)+offset
                    if not g:HitsWall(p.x+math.cos(a)*35,p.y+math.sin(a)*35,p.r) then
                        dx=math.cos(a) dy=math.sin(a) turned=true break
                    end
                end
                if not turned then dx=0 dy=-1 end
            end
            if p.hp<p.maxHp*0.45 then g:Cast("potion") end
            local near=g:Nearest(130)
            if near then g:Cast("burst") g:Cast("whirl") end
            g:Cast("blade")
            g:Update(0.034,dx,dy)
            frames=frames+1
            assert(#g.loadout<=6 and g.gold>=0 and p.hp==p.hp,"bot economy or HP invariant")
        end
    end
    assert(g.state=="dead" or g.state=="win","full run reaches a terminal state")
    print("[SurvivorBalance] "..cjson.encode({state=g.state,wave=g.wave,seconds=g.runTime,
        kills=g.kills,materials=g.earnedGold,weapons=#g.loadout,items=#g.items,frames=frames,
        hp=g.player.hp,maxHp=g.player.maxHp,armor=g.player.def}))
    -- Contrast with standing still: combat should reward steering and shopping.
    local idle=Dungeon.New({}) idle:SetWeapon(2) idle:Start()
    local idleFrames=0
    while idle.state~="dead" and idle.state~="win" and idleFrames<10000 do
        if idle.state=="talent" then idle:ChooseTalent(1)
        elseif idle.state=="shop" then idle:BeginWave()
        else idle:Update(0.034,0,0) idleFrames=idleFrames+1 end
    end
    assert(idle.state=="dead","standing still without upgrades must not auto-clear eight waves")
    print("[SurvivorIdle] "..cjson.encode({state=idle.state,wave=idle.wave,seconds=idle.runTime,kills=idle.kills}))
end
