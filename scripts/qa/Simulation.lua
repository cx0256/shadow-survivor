---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type SurvivorRulesAPI
local Survival=require "Survival"
local passed=0
local function check(value,message) assert(value,message) passed=passed+1 end
local function game()
    local g=Dungeon.New({}) g:Start() g.enemies={} return g
end
local function shop(g)
    g.waveTime=0.001 g:Update(0.02,0,0)
    while g.state=="talent" do
        g:ChooseTalent(1)
    end
    assert(g.state=="shop","expected shop")
end
local function weapon(kind,tier,cost)
    return {type="weapon",kind=kind,tier=tier,cost=cost or 10,locked=false,sold=false}
end
local g=game()
check(g.wave==1 and g.waveActive and #g.loadout==1,"run starts with one owned weapon")
check(g.player.hp==100 and g.player.hp==g.player.maxHp,"short-run base HP is fully restored")
local meta=Dungeon.New({hp=5,atk=5}) meta:Start()
check(meta.player.hp==100 and meta.player.atk==16,"legacy permanent buffs do not distort new survivor balance")
local duration=0 for _,v in ipairs(Survival.Durations) do duration=duration+v end
check(duration==305,"full combat budget is 305 seconds")
g:Update(0.02,0,0)
check(g.wave==1 and not g.portal,"empty arena does not skip timed wave")
local before=g.waveTime g.state="paused" g:Update(1,1,0)
check(g.waveTime==before and g.runTime<0.1,"pause freezes combat countdown")
g=game() g.player.x=160 g.player.y=312 g:Move(g.player,150,0)
check(g.player.x<=177,"pillar blocks actor movement")
g:Move(g.player,-3000,-3000)
check(not g:HitsWall(g.player.x,g.player.y,g.player.r),"large movement cannot tunnel through walls")
g=game() g.player.x=400 g.player.y=320
local a=g:SpawnEnemy("skeleton",500,320,false)
local b=g:SpawnEnemy("skeleton",580,320,false)
local c=g:SpawnEnemy("skeleton",650,320,false)
g:Shoot("arrow",0,10000) g:UpdateShots(0.5)
check(a.dead and b.dead and not c.dead,"swept arrows hit exactly two targets")
check(g.gold==0 and g.player.xp==0,"kills drop resources instead of instantly granting XP and gold")
local drops=#g.drops g:Kill(a)
check(g.kills==2 and #g.drops==drops,"death callbacks cannot duplicate drops")
g=game() g.player.x=160 g.player.y=312
a=g:SpawnEnemy("skeleton",300,312,false)
g:Shoot("arrow",0,10000) g:UpdateShots(0.5)
check(not a.dead,"pillars block projectiles before targets")
g=game() g.player.x=400 g.player.y=320
a=g:SpawnEnemy("zombie",500,320,false) b=g:SpawnEnemy("zombie",530,345,false)
g:Shoot("fireball",0,25) g:UpdateShots(0.4)
check(a.hp<a.maxHp and b.hp<b.maxHp,"fireball deals splash damage")
g=game() g.player.explode=1
a=g:SpawnEnemy("bat",450,320,false) b=g:SpawnEnemy("bat",480,320,false) c=g:SpawnEnemy("bat",510,320,false)
g:DamageEnemy(a,10000,false)
check(g.kills==3,"chain explosions award each enemy once")
g=game() g:GainXp(200) g:PresentTalent()
check(g.pendingLevels>0 and g.state=="playing","level choices are deferred while combat is active")
local levels=g.pendingLevels shop(g)
check(#g.talents==levels and g.pendingLevels==0,"all queued level choices are awarded before shop")
g=game() g.gold=29 g.player.harvest=4
g.drops={{kind="material",x=80,y=140,value=5,xp=2,collected=false}}
shop(g)
check(g.lastWave.materials==5 and g.lastWave.interest==3 and g.lastWave.harvest==12 and g.gold==49,"wave bell sweeps materials then applies interest and harvest exactly once")
local bank=g.gold Survival.EndWave(g)
check(g.gold==bank,"wave settlement cannot be repeated")
check(g:BeginWave() and g.wave==2 and not g:BeginWave(),"next wave requires shop and cannot double-start")
g=game() shop(g) g.gold=100
g.shop={weapon(2,1),weapon(1,1),weapon(3,1),weapon(2,2)}
check(g:BuyShop(1) and #g.loadout==2 and g.gold==90,"buying adds a second autonomous weapon")
check(g:BuyShop(2) and #g.loadout==2 and g.loadout[1].tier==2,"matching copy fuses instead of using an extra slot")
local spent=g.gold check(not g:BuyShop(2) and g.gold==spent,"sold offers cannot charge twice")
g.shop[1]=weapon(3,1,999)
check(not g:BuyShop(1) and g.gold==spent,"insufficient balance does not mutate inventory")
g.loadout={{kind=1,tier=2,cd=0,angle=0},{kind=2,tier=2,cd=0,angle=0},{kind=3,tier=2,cd=0,angle=0},
    {kind=1,tier=3,cd=0,angle=0},{kind=2,tier=3,cd=0,angle=0},{kind=3,tier=3,cd=0,angle=0}}
g.gold=100 g.shop[1]=weapon(1,1)
check(not g:BuyShop(1) and g.gold==100 and #g.loadout==6,"full slots reject purchases without losing money")
g.shop[1]=weapon(1,2)
check(g:BuyShop(1) and #g.loadout==6 and g.loadout[1].tier==3,"full slots still allow matching fusion")
g=game() shop(g) g.gold=100 g:LockOffer(1)
local locked=g.shop[1] local cost=g:RerollCost()
check(g:RerollShop() and g.shop[1]==locked and g.gold==100-cost,"reroll preserves locked offer and charges once")
check(g:RerollCost()>cost,"repeated refreshes become more expensive")
g:BeginWave() shop(g)
check(g.shop[1]==locked and locked.locked,"locked offer survives next combat wave")
for _,offer in ipairs(g.shop) do offer.locked=true end
bank=g.gold
check(not g:RerollShop() and g.gold==bank,"fully locked shop cannot charge useless refresh")
g=game() shop(g) g.gold=100
g.shop[1]={type="item",item=Survival.Items[1],cost=10,sold=false,locked=false}
local hp=g.player.maxHp local base=g:WeaponStats(g.loadout[1]).damage
g:BuyShop(1)
check(g.player.maxHp==hp-15 and g:WeaponStats(g.loadout[1]).damage>base,"glass build gains damage with an actual health tradeoff")
g.shop[2]={type="item",item=Survival.Items[2],cost=10,sold=false,locked=false}
local armor=g.player.def local cooldown=g:WeaponStats(g.loadout[1]).cooldown
g:BuyShop(2)
check(g.player.def==armor-2 and g:WeaponStats(g.loadout[1]).cooldown<cooldown,"attack-speed item trades away armor")
local normal=g:WeaponStats(g.loadout[1]).cooldown
g.loadout[2]={kind=1,tier=1,cd=0,angle=0}
check(g:WeaponStats(g.loadout[1]).cooldown<normal,"two swords activate melee set attack speed")
g.loadout={{kind=2,tier=1,cd=0,angle=0},{kind=2,tier=2,cd=0,angle=0},{kind=2,tier=3,cd=0,angle=0}}
check(g:WeaponStats(g.loadout[1]).pierce==3,"three bows activate extra penetration")
check(g:SellWeapon(1) and #g.loadout==2,"recycling frees a weapon slot")
g:SellWeapon(1) bank=g.gold
check(not g:SellWeapon(1) and g.gold==bank,"last weapon cannot be recycled")
g=game()
for wave=1,8 do
    g.waveTime=0.001 g:Update(0.02,0,0)
    while g.state=="talent" do
        g:ChooseTalent(1)
    end
    if wave<8 then assert(g.state=="shop") g:BeginWave() end
end
check(g.state=="win" and g.wave==8 and g.save.clears==1,"eight timed waves lead to a single win settlement")
local runs=g.save.runs g:Finish(true)
check(g.save.runs==runs and g.save.clears==1,"repeated final settlement is idempotent")
g:Start()
check(g.wave==1 and #g.loadout==1 and #g.items==0 and g.gold==0,"restart clears all run-specific purchases")
g=game() g.player.invuln=0 g:Hurt(10000)
check(g.state=="dead" and g.save.runs==1,"lethal damage ends and settles run once")
return passed
