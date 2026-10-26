-- Ordinary spawn placement at center, walls, corners and both pillar edges.
-- These checks protect readable arrivals; they do not certify human difficulty.
require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type SurvivorRulesAPI
local Survival=require "Survival"

DungeonApp.onReady=function()
    DungeonApp.testing=true
    math.randomseed(20261026)
    local checks,arrivals,minimum,maximum=0,0,math.huge,0
    local function check(ok,message) assert(ok,message) checks=checks+1 end
    local points={{480,315},{65,113},{895,113},{65,511},{895,511},{480,113},{480,511},{255,312},{700,312}}
    local kinds={}
    for wave=1,8 do
        kinds[wave]={}
        for _,point in ipairs(points) do
            local g=Dungeon.New({}) g:Start()
            g.wave=wave g.waveTime=20 g.player.x=point[1] g.player.y=point[2]
            local scheduled=0
            for _=1,20 do
                g.enemies={} g.spawnTimer=0
                Survival.Spawn(g,0.034)
                scheduled=scheduled+#g.enemies
                for _,e in ipairs(g.enemies) do
                    local d=math.sqrt((e.x-g.player.x)^2+(e.y-g.player.y)^2)
                    minimum=math.min(minimum,d) maximum=math.max(maximum,d)
                    check(d>=150,"new arrivals preserve a safe player gap even in arena corners")
                    check(d<=260,"regular arrivals stay close enough to enter the action promptly")
                    check(not g:HitsWall(e.x,e.y,e.r),"new arrivals never intersect walls or pillars")
                    check(e.born<=-0.24,"all regular arrivals provide the full warning before acting")
                    kinds[wave][e.kind]=true arrivals=arrivals+1
                end
            end
            check(scheduled>=20,"corner placement maintains at least one arrival per scheduled group")
        end
        local diversity=0 for _ in pairs(kinds[wave]) do diversity=diversity+1 end
        check(diversity>=(wave==1 and 2 or wave==2 and 3 or wave==3 and 4 or 5),
            "successive groups contain the distinct enemy jobs introduced by this wave")
    end
    check(not kinds[1].hunter and kinds[2].hunter,"charging enemies enter after the introductory wave")
    check(not kinds[2].mage and kinds[3].mage,"ground denial arrives after learning to turn away from charges")
    local blocked=Dungeon.New({}) blocked:Start() blocked.enemies={}
    blocked.HitsWall=function() return true end blocked.spawnTimer=0
    Survival.Spawn(blocked,0.034)
    check(#blocked.enemies==0,"no legal spawn space skips the group instead of spawning at a fixed player position")
    for wave=2,8 do
        local g=Dungeon.New({}) g:Start() g.wave=wave g.waveTime=20 g.enemies={}
        -- Hold enemies alive and move old groups away to isolate the special
        -- enemy budget from incidental free-space crowding.
        for _=1,50 do
            for i,e in ipairs(g.enemies) do e.x=65+(i%3)*40 e.y=125+math.floor(i/3)*20 end
            g.spawnTimer=0 Survival.Spawn(g,0.034)
        end
        local hunters,mages=0,0
        for _,e in ipairs(g.enemies) do
            if e.kind=="hunter" then hunters=hunters+1 elseif e.kind=="mage" then mages=mages+1 end
        end
        check(#g.enemies<=64,"long-lived crowds respect the global active enemy budget")
        check(hunters<=4 and mages<=4,"regular arrivals cannot fill the arena with simultaneous special attacks")
    end
    print(string.format("[EnemyPressure] %d checks, %d arrivals, distance %.1f..%.1f, 8 wave decks passed",checks,arrivals,minimum,maximum))
end
