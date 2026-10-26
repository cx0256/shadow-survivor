-- Focused mechanism checks. Fixtures are isolated from the production save;
-- this entry does not make a claim about human enjoyment or run difficulty.
require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type {Roles: table[], Apply: fun(g: table), Merge: fun(g: table, index: number): boolean}
local Builds=require "Builds"
---@type SurvivorRulesAPI
local Survival=require "Survival"
---@type RunDirectorAPI
local Director=require "RunDirector"
---@type CombatFeelAPI
local Feel=require "CombatFeel"

DungeonApp.onReady=function()
    DungeonApp.testing=true
    math.randomseed(20261023)
    local checks=0
    local function check(ok,message) assert(ok,message) checks=checks+1 end
    local function close(a,b) return math.abs(a-b)<0.0001 end
    local function weapon(kind,tier) return {kind=kind,tier=tier,cd=0,angle=0} end
    local function game(starter,role)
        local g=Dungeon.New({})
        g:SetWeapon(starter or 1) g.role=role or 1 g:Start()
        g.enemies={}
        return g
    end
    local function enterShop(g)
        g.waveTime=0.001 g:Update(0.02,0,0)
        local menuSteps=0
        while g.state=="talent" do
            g:ChooseTalent(1)
            menuSteps=menuSteps+1 assert(menuSteps<100,"test shop menu must terminate")
        end
        assert(g.state=="shop","test fixture reaches real wave-end shop")
    end
    local function totalDps(g)
        local dps=0
        for _,w in ipairs(g.loadout) do
            local stats=g:WeaponStats(w)
            dps=dps+stats.damage/stats.cooldown
        end
        return dps
    end
    local function killOrdinary(g,count)
        for i=1,count do
            local enemy=g:SpawnEnemy("skeleton",450+i,240,false)
            g:Kill(enemy)
        end
    end

    -- 36 combinations, including the tier-III -> IV edge. DPS is calculated
    -- from public weapon statistics over all slots, not a duplicated formula.
    for role=1,4 do
        for kind=1,3 do
            for tier=1,3 do
                local g=game(kind,role)
                enterShop(g)
                g.autoFuse=false
                g.loadout={weapon(kind,tier),weapon(kind,tier)}
                local dps=totalDps(g)
                local resonance=g:WeaponCount(kind)
                local stats=g:WeaponStats(g.loadout[1])
                local staffBurn=math.floor(g:WeaponCount(3)/2)*4
                local label="role "..role..", weapon "..kind..", tier "..tier
                check(Builds.Merge(g,1) and #g.loadout==1 and g.loadout[1].tier==tier+1,
                    "matching fusion consumes two copies: "..label)
                check(totalDps(g)+0.0001>=dps,"fusion preserves total theoretical DPS: "..label)
                check(g:WeaponCount(kind)>=resonance,"fusion preserves resonance: "..label)
                local merged=g:WeaponStats(g.loadout[1])
                check(merged.cooldown<=stats.cooldown+0.0001 and merged.pierce>=stats.pierce
                    and math.floor(g:WeaponCount(3)/2)*4>=staffBurn,
                    "fusion keeps attack-speed, piercing and burning set benefits: "..label)
            end
        end
    end

    ---@type table
    local g=game()
    killOrdinary(g,8)
    check(g.frenzyCharge==8 and g.burstCount==0 and g.overdriveTime==0,
        "eight kills ready frenzy without automatically triggering it")
    ---@type string[]
    local blockedStates={"paused","shop","evolution","dead"}
    for _,state in ipairs(blockedStates) do
        g.state=state g:Cast("burst")
        check(g.frenzyCharge==8 and g.burstCount==0 and g.overdriveTime==0,
            "burst is blocked outside playing: "..state)
    end
    g.state="playing" g:Cast("burst")
    check(g.frenzyCharge==0 and g.burstCount==1 and close(g.overdriveTime,2) and g.burstRecovery>0,
        "ready playing burst consumes charge and starts exactly two seconds of power")
    local recovery=g.burstRecovery g:Cast("burst")
    check(g.burstCount==1 and g.burstRecovery==recovery,"repeated cast cannot duplicate a burst")
    local unready=game() killOrdinary(unready,7) unready:Cast("burst")
    check(unready.frenzyCharge==7 and unready.burstCount==0,"seven kills cannot trigger burst")
    for _=1,61 do Director.Frame(g,0.034) end
    killOrdinary(g,8) g:Cast("burst")
    check(g.frenzyCharge==8 and g.burstRecovery>0 and g.burstCount==1 and g.overdriveTime==0,
        "a refilled charge cannot bypass the recovery timer")
    for _=1,210 do Director.Frame(g,0.034) end
    g:Cast("burst")
    check(g.burstRecovery>0 and g.burstCount==2 and g.frenzyCharge==0,
        "refilled burst succeeds after the real recovery timer expires")

    -- Spawn the actual timed bounty, kill it, then collect its real drop.
    g=game(2)
    g.waveTime=g.waveDuration-6 Director.Frame(g,0)
    local bounty
    for _,e in ipairs(g.enemies) do if e.bounty then bounty=e break end end
    assert(bounty,"timed bounty fixture was spawned")
    g:Kill(bounty)
    check(g.bountyKills==1 and g.forgeVouchers==0,"bounty death alone does not award a forge voucher")
    local treasure
    for _,drop in ipairs(g.drops) do if drop.treasure then treasure=drop break end end
    assert(treasure,"bounty produces a treasure drop")
    Survival.Pickup(g,treasure)
    check(g.forgeVouchers==1 and treasure.collected,"actual bounty pickup grants one voucher")
    local bank=g.gold local xp=g.player.xp
    Survival.Pickup(g,treasure)
    check(g.forgeVouchers==1 and g.gold==bank and g.player.xp==xp,
        "repeated pickup cannot duplicate voucher, materials or XP")
    check(not g:ClaimForge() and g.forgeVouchers==1,"claim is blocked during combat without consuming voucher")
    enterShop(g)
    local claimed=g.forgeClaimed bank=g.gold
    check(g:ClaimForge() and g.forgeVouchers==0 and g.forgeClaimed==claimed+1
        and g.gold==bank and g.loadout[1].tier==2,"shop claim grants and fuses the starter without charging gold")
    check(not g:ClaimForge() and g.forgeClaimed==claimed+1,"empty voucher balance cannot repeat shop claim")
    -- A second bona fide treasure pickup supplies the full-inventory fixture.
    g:BeginWave() g.enemies={}
    g.waveTime=g.waveDuration-6 Director.Frame(g,0)
    bounty=nil
    for _,e in ipairs(g.enemies) do if e.bounty then bounty=e break end end
    assert(bounty,"second timed bounty fixture was spawned")
    g:Kill(bounty)
    for _,drop in ipairs(g.drops) do if drop.treasure then Survival.Pickup(g,drop) end end
    enterShop(g)
    g.autoFuse=false
    g.loadout={weapon(1,4),weapon(2,4),weapon(3,4),weapon(1,4),weapon(2,4),weapon(3,4)}
    bank=g.gold claimed=g.forgeClaimed
    check(not g:ClaimForge() and g.forgeVouchers==1 and g.forgeClaimed==claimed
        and #g.loadout==6 and g.gold==bank,"full slots preserve the unclaimed voucher and economy")
    check(g:SellWeapon(6) and g:ClaimForge() and g.forgeVouchers==0 and #g.loadout==6
        and g.loadout[6].kind==g.starter,"retained voucher is claimable after freeing a real slot")

    local function actualTreasure(run)
        run.waveTime=run.waveDuration-6 Director.Frame(run,0)
        local target
        for _,e in ipairs(run.enemies) do if e.bounty then target=e break end end
        assert(target,"forge selection fixture spawns a real bounty")
        run:Kill(target)
        for _,drop in ipairs(run.drops) do if drop.treasure then return drop end end
        error("forge selection fixture has a real treasure drop")
    end
    local chosen=game(1)
    Survival.Pickup(chosen,actualTreasure(chosen))
    enterShop(chosen)
    for _,invalid in ipairs({0,4,1.5,"bow"}) do
        local vouchers,gold,slots,claims=chosen.forgeVouchers,chosen.gold,#chosen.loadout,chosen.forgeClaimed
        check(not chosen:ClaimForge(invalid) and chosen.forgeVouchers==vouchers
            and chosen.gold==gold and #chosen.loadout==slots and chosen.forgeClaimed==claims,
            "invalid forge choice cannot consume voucher or inventory: "..tostring(invalid))
    end
    local choiceGold=chosen.gold
    check(chosen:ClaimForge(2) and chosen.forgeVouchers==0 and chosen.forgeClaimed==1
        and #chosen.loadout==2 and chosen.loadout[2].kind==2 and chosen.gold==choiceGold,
        "sword starter can explicitly choose a free bow from a treasure voucher")

    local unswept=game()
    local abandoned=actualTreasure(unswept)
    local ordinary={kind="material",x=100,y=140,value=5,xp=2,collected=false,treasure=false}
    unswept.drops[#unswept.drops+1]=ordinary
    Survival.EndWave(unswept)
    check(not abandoned.collected and unswept.forgeVouchers==0,
        "wave bell cannot automatically collect an abandoned treasure or grant its voucher")
    check(ordinary.collected and unswept.lastWave.materials==5 and unswept.player.xp==2,
        "wave bell continues collecting ordinary material rewards and their XP")

    -- XP opens only one ordinary growth choice at the wave boundary.
    for starter=1,3 do
        g=game(starter) g.player.x=400 g.player.y=250
        g:GainXp(12)
        check(g.state=="playing" and g.pendingLevels==1,"XP never interrupts combat with a contract screen")
        enterShop(g)
        check(g.state=="shop" and g.pendingLevels==0,"one attribute choice returns directly to shop")
        for kind=1,3 do
            g.shots={} g.melee={} g.enemies={}
            local w=weapon(kind,1)
            g:Attack(0,w)
            check(#g.shots==(kind==1 and 0 or 1),"ordinary attacks have no removed contract extra projectiles")
            check(close(g:WeaponStats(w).targetRange,Dungeon.Weapons[kind].range),
                "weapon targeting uses its actual range")
        end
    end

    local function hunterFixture(turn)
        local run=game()
        local p=run.player
        p.x=400 p.y=250 p.vx=100 p.vy=0 p.invuln=0
        local hunter=run:SpawnEnemy("hunter",250,250,false)
        hunter.bossCd=0
        run:UpdateEnemy(hunter,0.02)
        check(hunter.windup>0 and close(hunter.chargeX,1) and close(hunter.chargeY,0),
            "hunter shows a locked direction before the charge")
        local dx,dy=hunter.chargeX,hunter.chargeY
        local hx,hy=hunter.x,hunter.y
        if turn then run:Move(p,0,110) end
        run:UpdateEnemy(hunter,0.02)
        check(close(hunter.chargeX,dx) and close(hunter.chargeY,dy)
            and close(hunter.x,hx) and close(hunter.y,hy),
            "warning remains stationary and does not retarget a moved player")
        for _=1,60 do run:UpdateEnemy(hunter,0.02) end
        check(close(hunter.chargeX,dx) and close(hunter.chargeY,dy),
            "hunter preserves the visible direction throughout its charge")
        return run
    end
    local turned=hunterFixture(true)
    local straight=hunterFixture(false)
    check(turned.player.hp==turned.player.maxHp,"turning away from the locked lane avoids hunter damage")
    check(straight.player.hp<straight.player.maxHp,"staying in the locked lane takes real hunter contact damage")

    -- Additional regressions 196-200: routine-drop pressure must not bypass
    -- physical collection of a treasure or healing pickup.
    local capped=game()
    capped.player.xpNext=1000000000 -- isolate pickup healing from level-up healing
    capped.player.hp=capped.player.maxHp-30
    local protectedTreasure=actualTreasure(capped)
    local protectedHeal={kind="heal",x=100,y=150,value=0,xp=0,collected=false}
    capped.drops[#capped.drops+1]=protectedHeal
    local hpBefore=capped.player.hp
    killOrdinary(capped,105)
    check(not protectedTreasure.collected and capped.forgeVouchers==0,
        "drop pressure cannot remotely collect the oldest treasure or award its voucher")
    check(not protectedHeal.collected and capped.player.hp==hpBefore,
        "drop pressure cannot remotely drink a healing pickup")
    check(capped.earnedGold>0 and capped.player.xp>0,
        "ordinary material overflow still credits its real money and XP")
    check(#capped.drops<=100,"routine material overflow keeps the drop budget bounded")
    local protectedOnly=game()
    local extraTreasure=actualTreasure(protectedOnly)
    protectedOnly.drops={extraTreasure}
    for i=1,101 do
        protectedOnly.drops[#protectedOnly.drops+1]={kind="heal",x=100+i,y=150,value=0,xp=0,collected=false}
    end
    killOrdinary(protectedOnly,1)
    local onlyProtected=true
    for _,drop in ipairs(protectedOnly.drops) do
        if drop.collected or (drop.kind=="material" and not drop.treasure) then onlyProtected=false end
    end
    check(#protectedOnly.drops>=102 and onlyProtected and protectedOnly.forgeVouchers==0,
        "protected-only overflow preserves special rewards instead of silently collecting them")

    -- Additional regressions 201-205: the telegraphed diagonal hits a real side
    -- pillar. Damage kicks and a nearby enemy cannot bend that locked route.
    local lane=game()
    lane.loadout={} lane.spawnTimer=999 lane.bountySpawned=true lane.formationBeat=2
    lane.player.x=400 lane.player.y=390 lane.player.vx=0 lane.player.vy=0 lane.player.invuln=0
    local charger=lane:SpawnEnemy("hunter",100,210,false)
    charger.bossCd=0
    lane:UpdateEnemy(charger,0.02)
    local originX,originY=charger.x,charger.y
    local directionX,directionY=charger.chargeX,charger.chargeY
    local reach=235.2
    local wall=lane:WallFraction(originX,originY,
        originX+directionX*reach,originY+directionY*reach,charger.r)
    assert(charger.windup>0 and wall>0 and wall<1,"hunter regression lane intersects the real pillar")
    local expectedX,expectedY=originX+directionX*reach*wall,originY+directionY*reach*wall
    charger.kickX=700 charger.kickY=-600
    lane:UpdateEnemy(charger,0.02)
    check(close(charger.x,originX) and close(charger.y,originY)
        and charger.kickX==0 and charger.kickY==0,
        "hunter warning ignores incoming kicks and keeps its telegraphed origin")
    local crowd=lane:SpawnEnemy("skeleton",charger.x+1,charger.y,false)
    crowd.speed=0 crowd.attackCd=999
    lane:Update(0.02,0,0)
    check(close(charger.x,originX) and close(charger.y,originY),
        "real post-AI crowd separation cannot push the warning off its fixed lane")
    local sawCharge,stopped,onLane=false,false,true
    for _=1,100 do
        local locked=charger.windup>0 or charger.charge>0
        charger.kickX=700 charger.kickY=-600
        crowd.x=charger.x+1 crowd.y=charger.y
        lane:Update(0.02,0,0)
        local cross=(charger.x-originX)*directionY-(charger.y-originY)*directionX
        if locked and math.abs(cross)>0.0001 then onLane=false end
        if charger.charge>0 then sawCharge=true end
        if sawCharge and charger.windup<=0 and charger.charge<=0 then stopped=true break end
    end
    check(sawCharge and onLane,"hunter charge stays on the telegraphed line under kicks and crowd overlap")
    check(stopped and close(charger.x,expectedX) and close(charger.y,expectedY),
        "hunter charge stops at the exact previewed pillar endpoint instead of sliding around it")
    check(not lane:HitsWall(charger.x,charger.y,charger.r) and lane.player.hp==lane.player.maxHp,
        "stopped hunter neither penetrates the pillar nor damages the player sheltered behind it")

    -- Report the important tradeoff that panel DPS alone cannot answer. These
    -- are fixed-target measurements: real attack / sword sweep / projectile
    -- collisions, no crits, no enemy movement or newly spawned reinforcements.
    -- Neither build is asserted to clear faster; the measured difference is
    -- evidence to inspect when deciding how fusion should feel.
    for kind=1,3 do
        for _,scenario in ipairs({"crowd","thick"}) do
            for _,fused in ipairs({false,true}) do
                local run=game(kind)
                run.player.x=400 run.player.y=300 run.player.crit=0
                run.loadout=fused and {weapon(kind,2)} or {weapon(kind,1),weapon(kind,1)}
                local targetCount=0
                if scenario=="crowd" then
                    for _,x in ipairs({465,490,510}) do
                        for _,y in ipairs({258,286,314,342}) do
                            run:SpawnEnemy("bat",x,y,false) targetCount=targetCount+1
                        end
                    end
                else run:SpawnEnemy("boss",475,300,false) targetCount=1 end
                local frames,elapsed=0,0
                local dt=0.034
                while run.kills<targetCount and frames<1000 do
                    run.time=run.time+dt
                    for _,w in ipairs(run.loadout) do
                        w.cd=math.max(0,w.cd-dt)
                        if w.cd<=0 then
                            local target=run:Nearest(run:WeaponStats(w).targetRange)
                            if target then run:Attack(math.atan(target.y-run.player.y,target.x-run.player.x),w) end
                        end
                    end
                    Feel.UpdateSwords(run,dt) run:UpdateShots(dt)
                    frames=frames+1 elapsed=elapsed+dt
                end
                print("[EngagementFusion] "..cjson.encode({kind=kind,scenario=scenario,
                    loadout=fused and "II" or "I+I",clearTime=run.kills==targetCount and elapsed or -1,
                    kills=run.kills,targetCount=targetCount,frames=frames,theoreticalDps=totalDps(run)}))
            end
        end
    end

    print("[EngagementRules] "..checks.." mechanism checks passed")
end
