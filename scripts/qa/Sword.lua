require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type CombatFeelAPI
local Feel=require "CombatFeel"
local passed=0
local function check(ok,message) assert(ok,message) passed=passed+1 end
local function arena()
    local g=Dungeon.New({}) g:Start()
    g.enemies={} g.spawnTimer=999 g.player.x=480 g.player.y=320 g.player.crit=0
    return g
end
local function sweep(g,steps)
    for _=1,steps or 30 do Feel.UpdateSwords(g,0.01) end
end

DungeonApp.onReady=function()
    DungeonApp.testing=true
    local g=arena()
    local warning=g:SpawnEnemy("skeleton",540,320,false) warning.born=-0.25
    g:Update(0.02,0,0)
    check(not warning.dead and warning.hp==warning.maxHp and g.loadout[1].cd==0,"warning is never an attack target")
    g:Cast("whirl")
    check(warning.hp==warning.maxHp,"skills cannot hit invisible warning")
    g:Shoot("arrow",0,10000) g:UpdateShots(0.1)
    check(warning.hp==warning.maxHp and g.shots[1].remaining==2,"warning does not absorb projectile penetration")
    g:Update(0.034,0,0)
    check(#g.melee==0,"warning does not consume sword cooldown")

    for i=0,7 do
        g=arena()
        local a=i*math.pi/4
        local e=g:SpawnEnemy("zombie",480+math.cos(a)*88,320+math.sin(a)*88,false)
        g:Attack(a,g.loadout[1])
        check(e.hp==e.maxHp and #g.melee==1,"sword has windup before damage")
        sweep(g)
        check(e.hp==e.maxHp-20,"sword aims and hits in all eight directions exactly once")
    end

    g=arena()
    local a=g:SpawnEnemy("zombie",545,320,false)
    local b=g:SpawnEnemy("zombie",548,350,false)
    local behind=g:SpawnEnemy("zombie",415,320,false)
    local far=g:SpawnEnemy("zombie",630,320,false)
    g:Attack(0,g.loadout[1]) sweep(g)
    check(a.hp<a.maxHp and b.hp<b.maxHp,"one sweep cleaves multiple enemies")
    check(behind.hp==behind.maxHp and far.hp==far.maxHp,"sweep cannot hit behind or outside reach")
    local hp=a.hp sweep(g)
    check(a.hp==hp and #g.melee==0 and not g.loadout[1].swing,"completed swing never hits again")
    check(a.kickX>0 and a.stagger>0 and #g.particles>0,"hit creates directional knockback stagger and sparks")

    g=arena()
    local angle=Feel.HalfArc+0.06
    a=g:SpawnEnemy("zombie",480+math.cos(angle)*90,320+math.sin(angle)*90,false)
    g:Attack(0,g.loadout[1]) sweep(g)
    check(a.hp<a.maxHp,"enemy circle overlapping fan edge is hit")
    g=arena()
    a=g:SpawnEnemy("zombie",480+112+18,320,false)
    g:Attack(0,g.loadout[1]) sweep(g)
    check(a.hp<a.maxHp,"exact outer tangency agrees with target acquisition")

    g=arena() g.player.x=170 g.player.y=312
    a=g:SpawnEnemy("zombie",255,312,false)
    g:Attack(0,g.loadout[1]) sweep(g)
    check(a.hp==a.maxHp,"pillar blocks sword damage throughout sweep")

    g=arena() a=g:SpawnEnemy("zombie",892,350,false)
    g:DamageEnemy(a,1,false,{x=850,y=350,knockback=100})
    for _=1,20 do g:UpdateEnemy(a,0.01) end
    check(not g:HitsWall(a.x,a.y,a.r),"knockback cannot push through arena wall")

    g=arena() a=g:SpawnEnemy("boss",550,320,false)
    g:DamageEnemy(a,1,false)
    check(a.stagger==0 and a.kickX<50,"boss resists stun and heavy knockback")

    g=arena() g.player.haste=8
    g.loadout={{kind=1,tier=1,cd=0,angle=0},{kind=1,tier=2,cd=0,angle=0}}
    a=g:SpawnEnemy("zombie",548,320,false) a.hp=100000 a.maxHp=a.hp a.speed=0 a.atk=0
    local maxSwings=0
    for _=1,180 do
        a.x=548 a.y=320
        g:Update(0.01,0,0) maxSwings=math.max(maxSwings,#g.melee)
    end
    check(a.hp<a.maxHp and maxSwings<=2,"high haste and two swords keep independent bounded swings")
    check(#g.particles<=240,"feedback particle budget remains bounded")
    g.waveTime=0 g:Update(0.01,0,0)
    check(#g.melee==0 and not g.loadout[1].swing,"wave transition cancels all active blades")
    g:Start()
    check(g.combo==0 and #g.particles==0 and #g.melee==0,"restart resets feedback state")
    -- Exercise the actual native draw path at windup, mid-sweep and recovery.
    -- Headless mode yields no pixels: these checks do not establish appearance.
    local original=DungeonApp.game
    for _,age in ipairs({0.01,0.05,0.10,0.17,0.23}) do
        g=arena()
        a=g:SpawnEnemy("zombie",540,320,false)
        local hunter=g:SpawnEnemy("hunter",350,225,false)
        hunter.windup=0.65 hunter.chargeX=0.8 hunter.chargeY=0.6
        g:Attack(0,g.loadout[1]) Feel.UpdateSwords(g,age)
        DungeonApp.game=g
        HandleDungeonRender()
        check(true,"native draw path accepts each sword animation phase")
    end
    DungeonApp.game=original
    print("[SwordTests] "..passed.." sword and feedback checks passed")
end
