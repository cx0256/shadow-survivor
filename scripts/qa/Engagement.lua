-- Background comparison, using ordinary gameplay methods and isolated saves.
-- This measures outcomes and pacing; it does not certify human enjoyment.
-- circle vs eager isolates the active E burst on identical wall-only movement.
-- adaptive combines objective / threat steering and several active actions;
-- its result must not be interpreted as the isolated effect of any one change.
-- Optional globals set before requiring this entry:
-- DungeonEngagementConfig={seeds={20261023},strategies={"circle"},starter=1,
--     role=1,maxFrames=10000,maxRuns=1,dt=0.034,recipes=false}
-- recipes=false skips only recipe choices; it never disables normal game rules
-- or changes the shop economy, and leftover vouchers still buy real weapons.
-- A reduced maxFrames still has to permit a terminal result; use fewer seeds
-- or maxRuns to shorten acceptance runs without truncating the simulation.
require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"

local function length(x,y) return math.sqrt(x*x+y*y) end
local function unit(x,y)
    local d=length(x,y)
    if d<0.001 then return 0,0 end
    return x/d,y/d
end
local function ready(e) return not e.dead and e.born>=0.5 end
local function segmentDistance(px,py,ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    local size=dx*dx+dy*dy
    if size<0.001 then return length(px-ax,py-ay) end
    local t=math.max(0,math.min(1,((px-ax)*dx+(py-ay)*dy)/size))
    return length(px-(ax+t*dx),py-(ay+t*dy))
end

-- Circle steering sees the arena walls only. It never examines enemy,
-- projectile, drop or hazard positions, and never casts an active action.
local function circle(g)
    local p=g.player
    local a=g.runTime*0.6
    local dx,dy=unit(480+math.cos(a)*270-p.x,315+math.sin(a)*125-p.y)
    if not g:HitsWall(p.x+dx*35,p.y+dy*35,p.r) then return dx,dy end
    for _,offset in ipairs({0.7,-0.7,1.4,-1.4,2.1,-2.1}) do
        local turn=math.atan(dy,dx)+offset
        local tx,ty=math.cos(turn),math.sin(turn)
        if not g:HitsWall(p.x+tx*35,p.y+ty*35,p.r) then return tx,ty end
    end
    return 0,-1
end

local function objective(g)
    local p=g.player
    local tx,ty=480,315
    local best=-math.huge
    for _,e in ipairs(g.enemies) do
        if ready(e) then
            local d=length(e.x-p.x,e.y-p.y)
            local value=(e.bounty and 1000 or e.kind=="mage" and 330 or 150)-d
            if value>best then best=value tx=e.x ty=e.y end
        end
    end
    -- Collecting XP early and gold boxes is an actual objective. Healing is
    -- only attractive when missing HP; neither policy is granted resources.
    for _,drop in ipairs(g.drops) do
        if not drop.collected then
            ---@type number
            local value=(drop.kind=="heal" and p.hp<p.maxHp*0.65) and 650
                or drop.kind=="heal" and -1000 or drop.treasure and 600 or 210
            value=value-length(drop.x-p.x,drop.y-p.y)
            if value>best then best=value tx=drop.x ty=drop.y end
        end
    end
    return tx,ty
end

-- A deliberately small policy: choose among 16 movement directions, favor
-- objectives, avoid nearby bodies, and project warning circles / hostile shots
-- a fraction of a second forward. It has no knowledge of future spawn RNG.
local function adaptive(g)
    local p=g.player
    local tx,ty=objective(g)
    local gx,gy=unit(tx-p.x,ty-p.y)
    local bestScore,bx,by=-math.huge,0,0
    for i=0,15 do
        local a=i*math.pi/8
        local dx,dy=math.cos(a),math.sin(a)
        local nx,ny=p.x+dx*p.speed*0.32,p.y+dy*p.speed*0.32
        local score=(dx*gx+dy*gy)*2
        if g:HitsWall(nx,ny,p.r+5) then score=score-30 end
        for _,e in ipairs(g.enemies) do
            if ready(e) and not e.bounty then
                local gap=length(nx-e.x,ny-e.y)-e.r-p.r
                if gap<95 then score=score-(95-math.max(-30,gap))/19 end
                if e.kind=="hunter" and e.windup>0 then
                    -- Only the already locked and visible telegraph is used.
                    -- The hunter's unseen next aim / attack is never queried.
                    local lineGap=segmentDistance(nx,ny,e.x,e.y,
                        e.x+e.chargeX*235,e.y+e.chargeY*235)
                    local danger=e.r+p.r+12
                    if lineGap<danger then score=score-18-(danger-lineGap)/5 end
                end
            end
        end
        for _,hazard in ipairs(g.hazards) do
            local gap=length(nx-hazard.x,ny-hazard.y)-hazard.r-p.r
            if hazard.time<0.65 and gap<25 then score=score-(25-gap)/9 end
        end
        for _,shot in ipairs(g.shots) do
            if shot.enemy then
                local gap=length(nx-(shot.x+shot.vx*0.2),ny-(shot.y+shot.vy*0.2))-p.r-shot.r
                if gap<45 then score=score-(45-gap)/12 end
            end
        end
        if score>bestScore then bestScore=score bx=dx by=dy end
    end
    return bx,by
end

local function cast(g,skill,telemetry)
    if g.state~="playing" then return end
    local p=g.player
    if skill=="potion" then
        local before=p.potions g:Cast(skill)
        telemetry.potions=telemetry.potions+math.max(0,before-p.potions)
    elseif skill=="burst" then
        local before=g.burstCount g:Cast(skill)
        if g.burstCount>before then telemetry.skillsCast=telemetry.skillsCast+1 end
    else
        local key=skill=="dash" and "dashCd" or skill=="whirl" and "whirlCd" or "bladeCd"
        local before=p[key] g:Cast(skill)
        if p[key]>before then telemetry.skillsCast=telemetry.skillsCast+1 end
    end
end

local function actions(g,t)
    local p=g.player
    local close,bounty=0,false
    for _,e in ipairs(g.enemies) do
        if ready(e) and not e.bounty and length(e.x-p.x,e.y-p.y)<145+e.r then close=close+1 end
        if ready(e) and e.bounty and length(e.x-p.x,e.y-p.y)<230 then bounty=true end
    end
    if g.frenzyCharge>=8 and (g.burstRecovery or 0)<=0
        and (close>=3 or p.hp<p.maxHp*0.45 or bounty) then cast(g,"burst",t) end
    if p.hp<p.maxHp*0.42 then cast(g,"potion",t) end
    if g.state~="playing" then return end
    if close>=2 then cast(g,"whirl",t) end
    if g.state~="playing" then return end
    if g:Nearest(400) then cast(g,"blade",t) end
    if close>=4 and p.whirlCd>0.6 then cast(g,"dash",t) end
end

-- All policies make identical build decisions. Shop purchases use the public
-- affordability / slot checks, including one affordable reroll per visit.
local function recipes(g,enabled)
    if not enabled or type(g.RecipeStatus)~="function" then return end
    for i=0,2 do
        local kind=(g.starter-1+i)%3+1
        local status=g:RecipeStatus(kind)
        if status.canEvolve then g:EvolveWeapon(kind) end
    end
end
local function recipeReady(g,enabled)
    if not enabled or type(g.RecipeStatus)~="function" then return false end
    for kind=1,3 do if g:RecipeStatus(kind).canEvolve then return true end end
    return false
end
local function shop(g,t,enableRecipes)
    for i,offer in ipairs(g.shop) do if offer.type=="weapon" then g:BuyShop(i) end end
    for i=1,#g.shop do g:BuyShop(i) end
    if g.gold>=g:RerollCost()+20 and g:RerollShop() then
        for i,offer in ipairs(g.shop) do if offer.type=="weapon" then g:BuyShop(i) end end
        for i=1,#g.shop do g:BuyShop(i) end
    end
    recipes(g,enableRecipes)
    -- Spend remaining vouchers through the normal claim action. If the free
    -- copy reaches tier II and a recipe becomes ready, keep its required last
    -- voucher for the following recipe choice instead of spending it blindly.
    if type(g.ClaimForge)=="function" then
        while (g.forgeVouchers or 0)>0 and not recipeReady(g,enableRecipes) do
            local before=g.forgeVouchers
            g:ClaimForge()
            if (g.forgeVouchers or 0)>=before then break end
            t.forgeClaimed=t.forgeClaimed+before-g.forgeVouchers
        end
    end
    recipes(g,enableRecipes)
    assert(g:BeginWave(),"engagement shop must begin next wave")
end

local function talent(g)
    local choice=1
    for i,t in ipairs(g.choices) do
        if t.stat=="atk" or t.stat=="haste" or t.stat=="explode" then choice=i break end
    end
    g:ChooseTalent(choice)
end

local function invariant(g)
    local p=g.player
    assert(#g.loadout>=1 and #g.loadout<=6,"engagement owns 1..6 weapons")
    assert(g.gold>=0 and g.gold==g.gold,"engagement currency finite and nonnegative")
    assert(p.hp==p.hp and p.hp>=0 and p.hp<=p.maxHp+0.001 and p.maxHp<math.huge,"engagement HP bounds")
    assert(g.runTime==g.runTime and g.runTime>=0 and g.runTime<math.huge,"engagement clock finite")
    assert(p.potions>=0,"engagement potion count nonnegative")
end

DungeonApp.onReady=function()
    DungeonApp.testing=true -- Disables production save writes, not combat.
    local config=rawget(_G,"DungeonEngagementConfig") or {}
    local seeds=config.seeds or {20261023,20261024}
    local strategies=config.strategies or {"circle","eager","adaptive"}
    local starter=config.starter or 1
    local role=config.role or 1
    local dt=config.dt or 0.034
    local maxFrames=config.maxFrames or 10000
    local maxRuns=config.maxRuns or (#seeds*#strategies)
    assert(type(seeds)=="table" and #seeds>0,"engagement needs seed list")
    assert(type(strategies)=="table" and #strategies>0,"engagement needs strategy list")
    assert(starter>=1 and starter<=3 and starter%1==0,"valid engagement starter")
    assert(role>=1 and role<=4 and role%1==0,"valid engagement role")
    assert(dt>0 and dt<=0.034 and maxFrames>0 and maxRuns>0,"valid engagement limits")
    local runs=0
    for _,seed in ipairs(seeds) do
        for _,strategy in ipairs(strategies) do
            if runs>=maxRuns then break end
            assert(type(seed)=="number" and seed==seed,"engagement seed is numeric")
            assert(strategy=="circle" or strategy=="eager" or strategy=="adaptive","known engagement strategy")
            math.randomseed(seed)
            local g=Dungeon.New({})
            g:SetWeapon(starter) g.role=role g:Start()
            local t={seed=seed,strategy=strategy,starter=starter,role=role,
                damageTaken=0,potions=0,skillsCast=0,forgeClaimed=0,firstKillAt=-1}
            t.comparison=strategy=="adaptive" and "movement+E+J+K+F+dash"
                or strategy=="eager" and "circle+E" or "circle"
            local frames,menus=0,0
            while g.state~="dead" and g.state~="win" and frames<maxFrames do
                invariant(g)
                if g.state=="talent" then talent(g) menus=menus+1
                elseif g.state=="shop" then shop(g,t,config.recipes~=false) menus=menus+1
                elseif g.state=="playing" then
                    local dx,dy
                    if strategy=="adaptive" then dx,dy=adaptive(g) actions(g,t)
                    else
                        dx,dy=circle(g)
                        if strategy=="eager" and g.frenzyCharge>=8 and (g.burstRecovery or 0)<=0 then
                            cast(g,"burst",t)
                        end
                    end
                    if g.state=="playing" then
                        local hp=g.player.hp
                        g:Update(dt,dx,dy)
                        t.damageTaken=t.damageTaken+math.max(0,hp-g.player.hp)
                        frames=frames+1
                    end
                    if t.firstKillAt<0 and g.kills>0 then t.firstKillAt=g.runTime end
                else error("unhandled engagement state: "..tostring(g.state)) end
                assert(menus<2000,"engagement menu transitions terminate")
            end
            invariant(g)
            t.state=g.state t.wave=g.wave t.kills=g.kills t.hp=g.player.hp t.runTime=g.runTime
            t.bountyKills=g.bountyKills t.burstCount=g.burstCount
            t.burstImmediateKills=g.burstImmediateKills or 0
            t.frames=frames t.weapons=#g.loadout t.items=#g.items t.potionsRemaining=g.player.potions
            t.materials=g.earnedGold
            t.maxWeaponTier=0
            for _,w in ipairs(g.loadout) do t.maxWeaponTier=math.max(t.maxWeaponTier,w.tier) end
            t.recipesEnabled=config.recipes~=false
            t.weaponEvolutions=g.weaponEvolutions or {}
            t.recipeUnlocks=g.recipeUnlocks or {}
            t.recipeStats=g.recipeStats or {}
            t.firstRecipeUnlockAt=#t.recipeUnlocks>0 and t.recipeUnlocks[1].time or -1
            print("[EngagementRun] "..cjson.encode(t))
            assert(g.state=="dead" or g.state=="win","engagement run must terminate within frame budget")
            runs=runs+1
        end
        if runs>=maxRuns then break end
    end
    assert(runs>0,"engagement runs executed")
    print("[EngagementChecks] "..runs.." ordinary-input runs completed; no win requirement")
end
