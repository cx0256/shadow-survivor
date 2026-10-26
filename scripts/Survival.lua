---@class SurvivorRulesAPI
---@field Init fun(g: table)
---@field Start fun(g: table)
---@field BeginWave fun(g: table): boolean
---@field Buy fun(g: table, index: number): boolean, string
---@field Reroll fun(g: table): boolean
---@field RerollCost fun(g: table): number
---@field Lock fun(g: table, index: number)
---@field Sell fun(g: table, index: number): boolean
---@field Stats fun(g: table, w: table, defs: table): table
---@field Count fun(g: table, kind: number): number
---@field Pickup fun(g: table, item: table)
---@field Frame fun(g: table, dt: number)
---@field EndWave fun(g: table)
---@field AddWeapon fun(g: table, kind: number, tier: number): boolean, string
---@field Items table[]
---@field Durations number[]
---@field ClaimForge fun(g: table, kind?: number): boolean, string
---@field GenerateOffer fun(g: table, index: number): table
---@field Spawn fun(g: table, dt: number)
-- Short-run survivor rules. Combat stays in Dungeon; this module owns the
-- wave/shop economy and the six independent weapon slots.
local Survival={}
---@type {Roles: table[], Apply: fun(g: table), Merge: fun(g: table, index: number): boolean}
local Builds=require "Builds"
---@type RunDirectorAPI
local Director=require "RunDirector"
Survival.Durations={20,25,30,35,40,45,50,60}
-- Rotate through an encounter deck rather than rolling the same fodder type
-- several times in a row. Later waves mix enemies with different jobs:
-- bodies block space, bats flank, hunters commit to lanes, mages deny ground.
local SPAWN_DECKS={
    {"skeleton","bat","skeleton","skeleton","bat"},
    {"bat","skeleton","hunter","bat","skeleton"},
    {"skeleton","mage","bat","hunter","skeleton"},
    {"zombie","bat","skeleton","hunter","mage","skeleton"},
    {"skeleton","hunter","bat","mage","zombie","bat"},
    {"zombie","hunter","mage","bat","skeleton","mage"},
    {"bat","hunter","zombie","mage","skeleton","hunter"},
    {"zombie","bat","mage","hunter","skeleton","zombie"},
}
Survival.Items={
    {name="玻璃之心",desc="伤害 +25% / 生命上限 -15",cost=24,mods={damage=0.25,hp=-15}},
    {name="狂战护符",desc="攻速 +25% / 护甲 -2",cost=22,mods={haste=0.25,def=-2}},
    {name="厚重板甲",desc="护甲 +4 / 移速 -18",cost=20,mods={def=4,speed=-18}},
    {name="拾荒口袋",desc="每波收获 +8 / 拾取范围 +25",cost=18,mods={harvest=8,pickup=25}},
    {name="血色契约",desc="吸血 +6% / 生命上限 -10",cost=23,mods={leech=0.06,hp=-10}},
    {name="跑鞋",desc="移速 +25 / 伤害 -5%",cost=16,mods={speed=25,damage=-0.05}},
    {name="火种",desc="命中灼烧 +5/秒",cost=24,mods={burn=5}},
    {name="爆破药剂",desc="击杀爆炸 +1 / 护甲 -1",cost=30,mods={explode=1,def=-1}},
    {name="再生种子",desc="每秒回复 +0.8 / 攻速 -8%",cost=20,mods={regen=0.8,haste=-0.08}},
    {name="猎人镜片",desc="暴击 +12% / 生命上限 -6",cost=18,mods={crit=0.12,hp=-6}},
    {name="急救包",desc="立即回复40%生命 / 额外药水 +1",cost=14,mods={heal=0.4,potion=1}},
    {name="磨刀石",desc="所有武器基础攻击 +4",cost=20,mods={atk=4}},
}

---@param g table
function Survival.Init(g)
    g.starter=1
    g.role=1 g.autoFuse=true
    g.waveMax=8
    g.waveTime=0
    g.waveDuration=0
    g.waveActive=false
    g.overdriveTime=0 g.frenzyCharge=0
    g.spawnTimer=0
    g.spawnIndex=0 g.spawnAngle=0
    g.loadout={}
    g.shop={}
    g.items={}
    g.rolls=0
    g.shopRevision=0
    g.earnedGold=0
    g.waveKills=0
    g.waveIncome=0
    g.lastWave={kills=0,materials=0,interest=0,harvest=0}
    g.returnState="shop"
    g.bossKilled=false
    g.player.damage=1
    g.player.harvest=0
    g.player.pickup=95
    g.player.regen=0
    g.player.atk=16
    g.player.maxHp=100 g.player.hp=100
    g.player.speed=235
    g.player.crit=0.05
    g.player.potions=2
end

---@param g table
function Survival.Start(g)
    local saved,starter,muted,role=g.save,g.starter,g.soundMuted,g.role
    g:Init(saved)
    g.starter=starter
    g.role=role Builds.Apply(g)
    g.soundMuted=muted
    g.weapon=starter
    g.loadout={{kind=starter,tier=1,cd=0,angle=-math.pi/2}}
    g.gold=0 g.player.hp=g.player.maxHp
    -- Broad arena with only two side pillars, leaving space to kite crowds.
    g.pillars={{x=192,y=288,w=48,h=48},{x=720,y=288,w=48,h=48}}
    g:BeginWave()
end

---@param g table
function Survival.BeginWave(g)
    if g.settled or g.waveActive then return false end
    if g.wave>0 and g.state~="shop" then return false end
    g.wave=g.wave+1
    g.floor=math.ceil(g.wave/2) -- retained only as an enemy scaling tier
    g.waveDuration=Survival.Durations[g.wave]
    g.waveTime=g.waveDuration
    g.waveActive=true
    g.state="playing"
    g.enemies={} g.shots={} g.hazards={} g.drops={} g.effects={} g.floats={}
    g.melee={} g.particles={} g.combo=0 g.comboTime=0 g.shake=0 g.hitPulse=0
    for _,w in ipairs(g.loadout) do w.swing=false end
    g.spawnTimer=0.4
    g.spawnIndex=math.random(#SPAWN_DECKS[g.wave])-1
    g.spawnAngle=math.random()*math.pi*2
    g.waveKills=0 g.waveIncome=0
    g.player.x=480 g.player.y=380 g.player.invuln=1
    g.player.hp=math.min(g.player.maxHp,g.player.hp+g.player.maxHp*0.12)
    for i,w in ipairs(g.loadout) do w.cd=(i-1)*0.08 end
    g:Banner("第 "..g.wave.." / 8 波 · 生存 "..g.waveDuration.." 秒")
    Director.BeginWave(g)
    if g.wave==4 then
        g:SpawnEnemy("zombie",480,155,true).born=-0.25
        g:Banner("精英来袭 · 留意远程敌人")
    elseif g.wave==8 then
        g:SpawnEnemy("boss",480,155,false).born=-0.25
        g:Banner("最终波 · 生存60秒或击败首领")
    end
    return true
end

---@param g table
function Survival.Count(g,kind)
    local count=0
    for _,w in ipairs(g.loadout) do if w.kind==kind then count=count+2^(w.tier-1) end end
    return math.min(6,count)
end

---@param g table
function Survival.Stats(g,w,definitions)
    local base=definitions[w.kind]
    local melee=Survival.Count(g,1)
    local burst=g.overdriveTime>0
    -- A fused bow puts some growth into cadence. Pure damage upgrades waste
    -- most of their benefit against small enemies and lose parallel targeting.
    -- 1.43 / 0.65 = 2.2: the total theoretical fusion gain stays consistent.
    local cadence=w.kind==2 and 0.65^(w.tier-1) or 1
    return {range=base.range,targetRange=base.range,
        damage=g.player.atk*base.damage*2.2^(w.tier-1)*cadence*math.max(0.2,g.player.damage)*(burst and 1.2 or 1)*Builds.Roles[g.role].damage[w.kind],
        cooldown=base.cooldown*cadence/(math.max(0.25,g.player.haste+(w.kind==1 and melee>=2 and (melee>=6 and 0.5 or melee>=4 and 0.35 or 0.2) or 0))*(burst and 1.45 or 1)),
        pierce=w.kind==2 and (2+(Survival.Count(g,2)>=3 and 1 or 0)) or 1}
end

---@param g table
function Survival.Pickup(g,item)
    if item.collected then return end
    item.collected=true
    if item.kind=="heal" then
        g.player.hp=math.min(g.player.maxHp,g.player.hp+14)
        g:Float(item.x,item.y,"+14",{119,225,145})
    else
        if item.treasure then
            g.forgeVouchers=g.forgeVouchers+1
            g:Banner("夺宝奖励 · 波间免费自选一把武器")
        end
        g:AddGold(item.value)
        g.waveIncome=g.waveIncome+item.value
        g:GainXp(item.xp)
    end
end

---@param g table
function Survival.ClaimForge(g,kind)
    if g.state~="shop" or g.forgeVouchers<=0 then return false,"没有可领取的夺宝武器" end
    kind=kind or g.starter
    if type(kind)~="number" or kind<1 or kind>3 or kind%1~=0 then return false,"请选择剑、弓或法杖" end
    local ok,reason=Survival.AddWeapon(g,kind,1)
    if not ok then return false,reason end
    g.forgeVouchers=g.forgeVouchers-1 g.forgeClaimed=g.forgeClaimed+1
    g.shopRevision=g.shopRevision+1
    return true,"夺宝武器已领取：可扩充，也可与同阶武器合成"
end

---@param g table
---@return table
function Survival.GenerateOffer(g,index)
    -- One visible recipe supply slot provides a route through bad luck. It is
    -- still bought with normal materials and never overwrites a locked offer.
    if index==1 then
        local status=g:RecipeStatus(g.starter)
        if not status.unlocked and #g.recipeUnlocks<g.recipeLimit then
            if not status.weaponReady then
                return {type="weapon",kind=g.starter,tier=1,cost=13+g.wave*3,
                    locked=false,sold=false,recipeHint=true}
            elseif not status.itemReady then
                for _,item in ipairs(Survival.Items) do
                    if item.name==status.item then
                        return {type="item",item=item,cost=item.cost+g.wave*2,
                            locked=false,sold=false,recipeHint=true}
                    end
                end
            end
        end
    end
    local tier=(g.wave>=5 and math.random()<0.18) and 2 or 1
    if index==1 or (index==4 and math.random()<0.6) then
        local kind=math.random(3)
        if index==1 and #g.loadout==1 then kind=g.loadout[1].kind%3+1 end
        return {type="weapon",kind=kind,tier=tier,cost=13+g.wave*3+(tier-1)*18,locked=false,sold=false}
    end
    local item=Survival.Items[math.random(#Survival.Items)]
    return {type="item",item=item,cost=item.cost+g.wave*2,locked=false,sold=false}
end

---@param g table
function Survival.OpenShop(g)
    g.state="shop"
    g.rolls=0
    for i=1,4 do
        if not g.shop[i] or not g.shop[i].locked or g.shop[i].sold then g.shop[i]=Survival.GenerateOffer(g,i) end
    end
    g.shopRevision=g.shopRevision+1
end

---@param g table
function Survival.EndWave(g)
    if not g.waveActive or g.state~="playing" then return end
    g.waveActive=false
    g.overdriveTime=0 g.frenzyCharge=0
    -- A special treasure must be reached before the bell; ordinary materials
    -- still sweep automatically so routine collection does not become busywork.
    for _,item in ipairs(g.drops) do
        if item.kind=="material" and not item.treasure then Survival.Pickup(g,item) end
    end
    local interest=math.min(8,math.floor(g.gold/10))
    local harvest=8+g.player.harvest
    g:AddGold(interest+harvest)
    g.lastWave={kills=g.waveKills,materials=g.waveIncome,interest=interest,harvest=harvest}
    g.enemies={} g.shots={} g.hazards={} g.drops={} g.melee={} g.particles={}
    g.echoes={}
    for _,w in ipairs(g.loadout) do w.swing=false end
    if g.wave>=g.waveMax then g:Finish(true) return end
    Survival.OpenShop(g)
    g.returnState="shop"
    if g.pendingLevels>0 then g.state="playing" g:PresentTalent() end
end

-- Spawn a readable group near the action, with a full 0.75 second warning.
-- Never fall back to a fixed point that could now be occupied by the player.
-- The fan leaves the opposite half of the arena open for a deliberate escape.
---@param g table
---@param angle number
local function spawnSpot(g,angle)
    for attempt=1,48 do
        local radius=155+math.random()*100
        local offset=attempt==1 and 0 or math.ceil((attempt-1)/2)*0.31*(attempt%2==0 and 1 or -1)
        local x=g.player.x+math.cos(angle+offset)*radius
        local y=g.player.y+math.sin(angle+offset)*radius
        if not g:HitsWall(x,y,24) then
            local clear=true
            for _,e in ipairs(g.enemies) do
                if not e.dead and (e.x-x)^2+(e.y-y)^2<(e.r+22)^2 then clear=false break end
            end
            if clear then return x,y end
        end
    end
    return nil,nil
end

---@param g table
function Survival.Spawn(g,dt)
    g.spawnTimer=g.spawnTimer-dt
    if g.spawnTimer>0 then return end
    local rush=g.waveTime<10
    g.spawnTimer=math.max(0.38,0.82-g.wave*0.038)*(rush and 0.8 or 1)
    local living=0
    local counts={hunter=0,mage=0}
    for _,e in ipairs(g.enemies) do
        if not e.dead then
            living=living+1
            if counts[e.kind] then counts[e.kind]=counts[e.kind]+1 end
        end
    end
    if living>=64 then return end
    local count=math.min(5,2+math.floor(g.wave/3)+(rush and 1 or 0))
    local deck=SPAWN_DECKS[g.wave]
    local specialCap=math.min(4,2+math.floor(g.wave/3))
    for i=1,math.min(count,64-living) do
        g.spawnIndex=g.spawnIndex+1
        local kind=deck[(g.spawnIndex-1)%#deck+1]
        if counts[kind] and counts[kind]>=specialCap then kind="skeleton" end
        local x,y=spawnSpot(g,g.spawnAngle+(i-(count+1)/2)*0.42)
        if x and y then
            local e=g:SpawnEnemy(kind,x,y,false)
            e.born=-0.25
            if counts[kind] then counts[kind]=counts[kind]+1 end
        end
    end
    g.spawnAngle=g.spawnAngle+2.3999632297
end

---@param g table
function Survival.Frame(g,dt)
    local p=g.player
    p.hp=math.min(p.maxHp,p.hp+p.regen*dt)
    g.waveTime=math.max(0,g.waveTime-dt)
    Survival.Spawn(g,dt)
    Director.Frame(g,dt)
    if g.state~="playing" then return end
    for i=#g.drops,1,-1 do
        local item=g.drops[i]
        local dx,dy=p.x-item.x,p.y-item.y
        local d=math.sqrt(dx*dx+dy*dy)
        if d<p.pickup+(g.overdriveTime>0 and 240 or 0) and d>1 then
            local step=math.min(d,520*dt)
            item.x=item.x+dx/d*step item.y=item.y+dy/d*step
        end
        if d<22 then Survival.Pickup(g,item) table.remove(g.drops,i) end
    end
    if g.waveTime<=0 or (g.wave==8 and g.bossKilled) then Survival.EndWave(g) end
end

---@param g table
function Survival.AddWeapon(g,kind,tier)
    -- Buying a matching copy fuses immediately; this also works at six slots.
    for _,w in ipairs(g.loadout) do
        if g.autoFuse and w.kind==kind and w.tier==tier and tier<4 then w.tier=w.tier+1 return true,"合成" end
    end
    if #g.loadout>=6 then return false,"武器槽已满" end
    g.loadout[#g.loadout+1]={kind=kind,tier=tier,cd=0,angle=-math.pi/2}
    return true,"购入"
end

---@param g table
function Survival.Buy(g,index)
    if g.state~="shop" then return false,"商店未开放" end
    local offer=g.shop[index]
    if not offer or offer.sold then return false,"已售出" end
    if g.gold<offer.cost then return false,"材料不足" end
    if offer.type=="weapon" then
        local ok,reason=Survival.AddWeapon(g,offer.kind,offer.tier)
        if not ok then return false,reason end
    else
        local p=g.player
        for stat,value in pairs(offer.item.mods) do
            if stat=="hp" then p.maxHp=math.max(20,p.maxHp+value) p.hp=math.min(p.hp,p.maxHp)
            elseif stat=="heal" then p.hp=math.min(p.maxHp,p.hp+p.maxHp*value)
            elseif stat=="potion" then p.potions=p.potions+value
            else p[stat]=p[stat]+value end
        end
        p.speed=math.max(100,p.speed) p.haste=math.max(0.25,p.haste)
        p.crit=math.min(0.85,p.crit)
        g.items[#g.items+1]=offer.item.name
    end
    g.gold=g.gold-offer.cost offer.sold=true offer.locked=false
    g.shopRevision=g.shopRevision+1
    return true,"购买成功"
end

---@param g table
function Survival.RerollCost(g) return 2+g.wave+g.rolls*2 end
---@param g table
function Survival.Reroll(g)
    if g.state~="shop" then return false end
    local cost=Survival.RerollCost(g)
    local unlocked=false
    for _,offer in ipairs(g.shop) do if not offer.locked then unlocked=true end end
    if not unlocked or g.gold<cost then return false end
    g.gold=g.gold-cost g.rolls=g.rolls+1
    for i,offer in ipairs(g.shop) do if not offer.locked then g.shop[i]=Survival.GenerateOffer(g,i) end end
    g.shopRevision=g.shopRevision+1
    return true
end
---@param g table
function Survival.Lock(g,index)
    local offer=g.shop[index]
    if g.state~="shop" or not offer or offer.sold then return end
    offer.locked=not offer.locked g.shopRevision=g.shopRevision+1
end
---@param g table
function Survival.Sell(g,index)
    if g.state~="shop" or #g.loadout<=1 or not g.loadout[index] then return false end
    local w=table.remove(g.loadout,index)
    g.gold=g.gold+math.floor((13+g.wave*3+(w.tier-1)*18)*0.5)
    g.shopRevision=g.shopRevision+1
    return true
end

return Survival
