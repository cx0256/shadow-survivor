-- Short-run recipe goals: upgraded weapon + relic + a treasure voucher.
-- This module never creates recursive attacks, extra projectiles, or DOT ticks.
local Recipes={}
---@type table[]
Recipes.Definitions={
    {kind=1,name="血月回斩",item="狂战护符",desc="每3次剑出手，周身回斩造成75%剑伤害\n触发间隔至少0.45秒"},
    {kind=2,name="追魂弹射",item="猎人镜片",desc="穿透命中后，追击180范围内新目标\n穿透耗尽追加2跳，每跳保留75%伤害"},
    {kind=3,name="余烬蔓延",item="火种",desc="持杖时，燃烧敌人死亡传火至110范围\n最多5个目标持续3秒，保留75%灼烧强度"},
}
local function valid(kind)
    return type(kind)=="number" and kind>=1 and kind<=3 and kind%1==0
end
local function ready(e) return not e.dead and e.born>=0.5 end

---@param g table
function Recipes.Init(g)
    g.weaponEvolutions={false,false,false}
    g.weaponEvolutionProgress={0,0,0}
    g.recipeRevision=0 g.recipeCleaveReadyAt=0
    g.recipeLimit=1
    g.recipeStats={cleaves=0,bounces=0,spreads=0}
    g.recipeUnlocks={}
end

---@param g table
---@param kind number
function Recipes.Status(g,kind)
    if not valid(kind) then
        return {kind=0,name="未知配方",item="",desc="",tier=0,weaponReady=false,
            itemReady=false,unlocked=false,canEvolve=false,stateText="无效配方"}
    end
    local def=Recipes.Definitions[kind]
    local tier=0
    for _,w in ipairs(g.loadout) do if w.kind==kind then tier=math.max(tier,w.tier) end end
    local itemReady=false
    for _,item in ipairs(g.items) do if item==def.item then itemReady=true break end end
    local unlocked=g.weaponEvolutions[kind]
    local full=#g.recipeUnlocks>=g.recipeLimit
    local state=unlocked and "本局已激活" or full and "本局进化核心已确定"
        or tier<2 and "需要II阶同类武器"
        or not itemReady and ("需要"..def.item) or g.forgeVouchers<=0 and "需要夺宝券"
        or g.state~="shop" and "在商店完成进化" or "配方齐备"
    return {kind=kind,name=def.name,item=def.item,desc=def.desc,tier=tier,weaponReady=tier>=2,
        itemReady=itemReady,unlocked=unlocked,
        canEvolve=g.state=="shop" and not unlocked and not full and tier>=2 and itemReady and g.forgeVouchers>=1,
        stateText=state}
end

---@param g table
---@param kind number
function Recipes.Evolve(g,kind)
    if not valid(kind) then return false,"请选择有效的武器配方" end
    if g.state~="shop" or g.settled then return false,"请在波间商店进化" end
    local status=Recipes.Status(g,kind)
    if not status.canEvolve then return false,status.stateText end
    g.forgeVouchers=g.forgeVouchers-1
    g.weaponEvolutions[kind]=true
    g.recipeRevision=g.recipeRevision+1 g.shopRevision=g.shopRevision+1
    g.recipeUnlocks[#g.recipeUnlocks+1]={kind=kind,name=status.name,time=g.runTime,wave=g.wave}
    g:Banner(status.name.." · 本局同类武器已进化")
    g:Effect(g.player.x,g.player.y,150,"evolve")
    return true,status.name.."已激活：武器与遗物保留，本局同类武器继承"
end

---@param g table
---@param w table
---@param stats table
function Recipes.AfterAttack(g,w,stats)
    if g.state~="playing" or w.kind~=1 or not g.weaponEvolutions[1] then return end
    g.weaponEvolutionProgress[1]=math.min(3,g.weaponEvolutionProgress[1]+1)
    if g.weaponEvolutionProgress[1]<3 or g.runTime<g.recipeCleaveReadyAt then return end
    g.weaponEvolutionProgress[1]=0 g.recipeCleaveReadyAt=g.runTime+0.45
    g.recipeStats.cleaves=g.recipeStats.cleaves+1
    local p=g.player
    g:Effect(p.x,p.y,160,"cleave")
    for _,e in ipairs(g.enemies) do
        if ready(e) and (e.x-p.x)^2+(e.y-p.y)^2<=(160+e.r)^2
            and g:WallFraction(p.x,p.y,e.x,e.y,2)>=1 then
            g:DamageEnemy(e,stats.damage*0.75,false,{x=p.x,y=p.y,knockback=58})
        end
    end
end

---@param g table
---@param shot table
---@param hitEnemy table
---@param x number
---@param y number
function Recipes.Bounce(g,shot,hitEnemy,x,y)
    if not g.weaponEvolutions[2] or shot.enemy or shot.kind~="arrow" or shot.originKind~=2 then return false end
    local extra=shot.remaining<=0
    if extra and (shot.bounces or 0)>=2 then return false end
    ---@type table|false
    local target=false
    local best=180^2
    for _,e in ipairs(g.enemies) do
        local d=(e.x-x)^2+(e.y-y)^2
        if e~=hitEnemy and ready(e) and not shot.hits[e] and d<=best
            and g:WallFraction(x,y,e.x,e.y,shot.r)>=1 then target=e best=d end
    end
    if not target then return false end
    local angle=math.atan(target.y-y,target.x-x)
    local speed=math.sqrt(shot.vx^2+shot.vy^2)
    shot.x=x shot.y=y shot.vx=math.cos(angle)*speed shot.vy=math.sin(angle)*speed
    if extra then
        shot.damage=shot.damage*0.75 shot.remaining=1 shot.bounces=(shot.bounces or 0)+1
    end
    shot.recipeGuided=true
    shot.life=math.max(shot.life,0.65)
    g.recipeStats.bounces=g.recipeStats.bounces+1
    g:Effect(x,y,19,"ricochet")
    return true
end

---@param g table
---@param e table
function Recipes.OnKill(g,e)
    if not g.weaponEvolutions[3] or e.burnTime<=0 or e.burnDamage<=0 then return end
    local equipped=false
    for _,w in ipairs(g.loadout) do if w.kind==3 then equipped=true break end end
    if not equipped then return end
    local targets={}
    for index,other in ipairs(g.enemies) do
        local d=(other.x-e.x)^2+(other.y-e.y)^2
        if other~=e and ready(other) and d<=110^2
            and g:WallFraction(e.x,e.y,other.x,other.y,2)>=1 then
            targets[#targets+1]={enemy=other,d=d,index=index}
        end
    end
    table.sort(targets,function(a,b) return a.d<b.d or (a.d==b.d and a.index<b.index) end)
    local n=math.min(5,#targets)
    if n>0 then g:Effect(e.x,e.y,110,"spread") end
    for i=1,n do
        local target=targets[i].enemy
        target.burnTime=math.max(target.burnTime,3)
        target.burnDamage=math.max(target.burnDamage,e.burnDamage*0.75)
        g.recipeStats.spreads=g.recipeStats.spreads+1
    end
end

return Recipes
