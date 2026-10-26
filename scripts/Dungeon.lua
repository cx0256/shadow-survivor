-- Engine-independent simulation. Coordinates use the original 960 x 624 arena.
-- Collision plan (all distances below are design-space pixels):
--   [48px wall]  (hero r=15) ---- arrow segment ---- (enemy r=12..27)
--   [pillar AABB] blocks every actor and projectile; segment hits are sorted
--   by travel distance, so a wall always wins over a target behind it.
-- Tangency is permitted for actors; projectiles include their radius in sweeps.
---@class DungeonModuleAPI
---@field New fun(saved: table): table
---@field Weapons table[]
---@type SurvivorRulesAPI
local Survival=require "Survival"
---@class CombatFeelAPI
---@field HalfArc number
---@field Init fun(g: table)
---@field Ready fun(e: table): boolean
---@field Death fun(g: table, e: table)
---@field Hit fun(g: table, e: table, crit: boolean, source?: table)
---@field Sword fun(g: table, w: table, angle: number, stats: table)
---@field UpdateSwords fun(g: table, dt: number)
---@field Update fun(g: table, dt: number)
---@type CombatFeelAPI
local Feel=require "CombatFeel"
---@class RunDirectorAPI
---@field Init fun(g: table)
---@field Kill fun(g: table, e: table)
---@field BeginWave fun(g: table)
---@field Frame fun(g: table, dt: number)
---@field Ignite fun(g: table): boolean
---@type RunDirectorAPI
local Director=require "RunDirector"
---@class WeaponEvolutionsAPI
---@field Init fun(g: table)
---@field Status fun(g: table, kind: number): table
---@field Evolve fun(g: table, kind: number): boolean, string
---@field AfterAttack fun(g: table, w: table, stats: table)
---@field Bounce fun(g: table, shot: table, hitEnemy: table, x: number, y: number): boolean
---@field OnKill fun(g: table, e: table)
---@field Definitions table[]
---@type WeaponEvolutionsAPI
local WeaponEvolutions=require "WeaponEvolutions"
local Dungeon = {}
Dungeon.__index = Dungeon

Dungeon.W = 960
Dungeon.H = 624
Dungeon.Weapons = {
    {id="sword", name="铁剑", detail="交替横斩 · 扇形击退", range=112, cooldown=0.54, damage=1.25, color={223,190,126}},
    {id="bow", name="游侠长弓", detail="高速箭矢 · 穿透两名敌人", range=460, cooldown=0.88, damage=0.95, color={111,213,173}},
    {id="staff", name="余烬法杖", detail="火球命中 · 范围爆炸", range=365, cooldown=1.20, damage=1.40, color={238,133,85}},
}
Dungeon.Talents = {
    {name="锋锐", desc="攻击力 +5", stat="atk", value=5},
    {name="坚韧", desc="生命上限 +28，并回复28点", stat="hp", value=28},
    {name="疾行", desc="移动速度 +22", stat="speed", value=22},
    {name="连斩", desc="攻击速度 +18%", stat="haste", value=0.18},
    {name="汲取", desc="造成伤害的5%回复生命", stat="leech", value=0.05},
    {name="烈焰", desc="攻击附加持续3秒的灼烧", stat="burn", value=7},
    {name="爆裂", desc="击杀触发65范围爆炸", stat="explode", value=1},
    {name="铁壁", desc="受到的伤害减少2点", stat="def", value=2},
    {name="暴击", desc="暴击概率 +10%", stat="crit", value=0.10},
}
local ENEMIES = {
    skeleton={hp=21,atk=10,speed=108,r=14,xp=4,sprite="SKEL"},
    bat={hp=12,atk=8,speed=172,r=12,xp=3,sprite="BAT"},
    zombie={hp=62,atk=16,speed=80,r=18,xp=6,sprite="ZOMBIE"},
    mage={hp=32,atk=12,speed=84,r=14,xp=5,sprite="MAGE"},
    hunter={hp=58,atk=16,speed=114,r=16,xp=7,sprite="HUNTER"},
    boss={hp=780,atk=23,speed=83,r=27,xp=80,sprite="BRUTE"},
}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function hunterLocked(e) return e.kind=="hunter" and (e.windup>0 or e.charge>0) end
local function number(v,default,max)
    if type(v)~="number" or v~=v then return default end
    return clamp(math.floor(v),0,max or 100000000)
end

---@return table
function Dungeon.New(saved)
    local self=setmetatable({},Dungeon)
    self:Init(saved or {})
    return self
end

function Dungeon:Init(saved)
    self.save={gold=number(saved.gold,0),runs=number(saved.runs,0),clears=number(saved.clears,0),
        kills=number(saved.kills,0),bestFloor=number(saved.bestFloor,0,5),
        hp=number(saved.hp,0,5),atk=number(saved.atk,0,5),bestWave=number(saved.bestWave,0,8)}
    self.state="title" --[[@as string]]
    self.weapon=1
    self.floor=1
    self.wave=0
    self.enemies={}
    self.shots={}
    self.hazards={}
    self.drops={}
    self.effects={}
    self.floats={}
    self.pillars={}
    self.choices={}
    self.talents={}
    self.equipment={}
    self.pendingLoot={}
    self.portal=false
    self.banner="暗影地牢"
    self.bannerTime=0
    self.time=0
    self.runTime=0
    self.gold=0
    self.kills=0
    self.settled=false
    self.saveDirty=false
    self.pendingLevels=0
    self.player={x=480,y=486,r=15,hp=150,maxHp=150,atk=20,speed=245,haste=1,leech=0,burn=0,explode=0,def=2,crit=0.08,
        level=1,xp=0,xpNext=26,aim=-math.pi/2,attackCd=0,invuln=0,dashTime=0,dashCd=0,dashX=0,dashY=-1,
        whirlCd=0,bladeCd=0,potions=3,hit=0,moving=false,walk=0,vx=0,vy=0}
    self.waveActive=false self.loadout={} self.returnState="shop"
    Survival.Init(self)
    Feel.Init(self)
    Director.Init(self)
    WeaponEvolutions.Init(self)
    self.player.xpNext=12
end

function Dungeon:Start() Survival.Start(self) end
function Dungeon:SetWeapon(index)
    if self.state=="title" and Dungeon.Weapons[index] then self.starter=index self.weapon=index end
end
function Dungeon:BeginWave() return Survival.BeginWave(self) end
function Dungeon:BuyShop(index) return Survival.Buy(self,index) end
function Dungeon:RerollShop() return Survival.Reroll(self) end
function Dungeon:RerollCost() return Survival.RerollCost(self) end
function Dungeon:LockOffer(index) Survival.Lock(self,index) end
function Dungeon:SellWeapon(index) return Survival.Sell(self,index) end
function Dungeon:WeaponStats(w) return Survival.Stats(self,w,Dungeon.Weapons) end
function Dungeon:WeaponCount(kind) return Survival.Count(self,kind) end
function Dungeon:ClaimForge(kind) return Survival.ClaimForge(self,kind) end
function Dungeon:RecipeStatus(kind) return WeaponEvolutions.Status(self,kind) end
function Dungeon:EvolveWeapon(kind) return WeaponEvolutions.Evolve(self,kind) end

function Dungeon:Banner(text)
    self.banner=text
    self.bannerTime=2.3
end



function Dungeon:HitsWall(x,y,r)
    if x-r<48 or x+r>912 or y-r<96 or y+r>528 then return true end
    for _,b in ipairs(self.pillars) do
        local dx=x-clamp(x,b.x,b.x+b.w)
        local dy=y-clamp(y,b.y,b.y+b.h)
        if dx*dx+dy*dy<r*r then return true end
    end
    return false
end

function Dungeon:Move(e,dx,dy)
    local steps=math.max(1,math.ceil(math.max(math.abs(dx),math.abs(dy))/6))
    for _=1,steps do
        if not self:HitsWall(e.x+dx/steps,e.y,e.r) then e.x=e.x+dx/steps end
        if not self:HitsWall(e.x,e.y+dy/steps,e.r) then e.y=e.y+dy/steps end
    end
end

function Dungeon:SpawnEnemy(kind,x,y,elite)
    local data=ENEMIES[kind]
    local scale=1+math.max(0,self.wave-1)*0.27
    local e={x=x,y=y,r=data.r,kind=kind,sprite=data.sprite,hp=data.hp*scale*(elite and 1.9 or 1),
        atk=data.atk*(1+math.max(0,self.wave-1)*0.13),speed=data.speed,xp=data.xp*(elite and 2 or 1),
        elite=elite or false,dead=false,hit=0,burnTime=0,burnDamage=0,attackCd=0.45,
        shootCd=0.9+(#self.enemies%4)*0.18,born=0.5,windup=0,bossCd=2.6,charge=0,chargeX=0,chargeY=0,chargeDistance=0,laneLocked=false,
        kickX=0,kickY=0,stagger=0,
        bounty=false,escapeTime=0}
    e.maxHp=e.hp
    if kind=="hunter" then e.bossCd=0.45 end
    self.enemies[#self.enemies+1]=e
    return e
end

function Dungeon:FreeSpot()
    for _=1,100 do
        local x,y=math.random(90,870),math.random(148,528)
        if not self:HitsWall(x,y,30) and distance({x=x,y=y},self.player)>215 then return x,y end
    end
    return 480,160
end



function Dungeon:Float(x,y,text,color)
    self.floats[#self.floats+1]={x=x,y=y,text=tostring(text),color=color or {237,215,171},life=0.85}
end

function Dungeon:Effect(x,y,r,kind)
    self.effects[#self.effects+1]={x=x,y=y,r=r,kind=kind,life=0.32,maxLife=0.32,angle=self.player.aim}
end

function Dungeon:AddGold(amount)
    self.gold=self.gold+amount
    self.earnedGold=self.earnedGold+amount
end

function Dungeon:GainXp(amount)
    local p=self.player
    p.xp=p.xp+amount
    while p.xp>=p.xpNext do
        p.xp=p.xp-p.xpNext
        p.level=p.level+1
        p.xpNext=math.floor(p.xpNext*1.22+10)
        p.maxHp=p.maxHp+6
        p.hp=math.min(p.maxHp,p.hp+6)
        self.pendingLevels=self.pendingLevels+1
    end
end

function Dungeon:PresentTalent()
    if self.state~="playing" or self.pendingLevels<=0 or self.waveActive then return end
    self.choices={}
    local pool={}
    for i=1,#Dungeon.Talents do pool[i]=i end
    for _=1,3 do
        local index=table.remove(pool,math.random(#pool))
        self.choices[#self.choices+1]=Dungeon.Talents[index]
    end
    self.state="talent"
end

function Dungeon:ChooseTalent(index)
    if self.state~="talent" or not self.choices[index] then return end
    local talent=self.choices[index]
    local p=self.player
    if talent.stat=="hp" then p.maxHp=p.maxHp+talent.value p.hp=math.min(p.maxHp,p.hp+talent.value)
    else p[talent.stat]=p[talent.stat]+talent.value end
    p.crit=math.min(0.85,p.crit)
    self.talents[#self.talents+1]=talent.name
    self.pendingLevels=self.pendingLevels-1
    self.choices={}
    self.state="playing"
    self:PresentTalent()
    if self.pendingLevels==0 then self.state=self.returnState end
end

function Dungeon:TrimDrops()
    -- Only routine materials may be credited remotely. Special treasure and
    -- healing stay on the field, including when they are the oldest drops.
    while #self.drops>100 do
        local ordinary=0
        for i,item in ipairs(self.drops) do
            if item.kind=="material" and not item.treasure then ordinary=i break end
        end
        if ordinary==0 then break end -- preserve protected drops over a hard cap
        Survival.Pickup(self,table.remove(self.drops,ordinary))
    end
end

function Dungeon:Kill(e)
    if e.dead then return end
    e.dead=true self.kills=self.kills+1 self.waveKills=self.waveKills+1
    Feel.Death(self,e)
    Director.Kill(self,e)
    WeaponEvolutions.OnKill(self,e)
    local value=e.bounty and 10 or e.kind=="boss" and 35 or e.elite and 12 or 1
    self.drops[#self.drops+1]={x=e.x,y=e.y,kind="material",value=value,xp=e.xp,collected=false,treasure=e.bounty}
    if math.random()<0.045 then self.drops[#self.drops+1]={x=e.x+10,y=e.y,kind="heal",value=0,xp=0,collected=false} end
    self:TrimDrops()
    self:Effect(e.x,e.y,e.r+8,"death")
    if e.kind=="boss" then self.bossKilled=true end
    if self.player.explode>0 then
        self:Effect(e.x,e.y,65,"fire")
        for _,other in ipairs(self.enemies) do
            if not other.dead and distance(e,other)<=65+other.r then self:DamageEnemy(other,18*self.player.explode,false) end
        end
    end
end

function Dungeon:DamageEnemy(e,raw,applyEffects,source)
    if not Feel.Ready(e) then return end
    local crit=applyEffects and math.random()<self.player.crit
    local damage=math.floor(raw*(crit and 1.7 or 1))
    e.hp=e.hp-damage
    e.hit=0.13
    Feel.Hit(self,e,crit,source)
    self:Float(e.x,e.y-e.r-10,(crit and "!" or "")..damage,crit and {255,213,95} or {230,220,200})
    if applyEffects then
        local p=self.player
        p.hp=math.min(p.maxHp,p.hp+math.min(damage,math.max(0,e.hp+damage))*p.leech)
        local burn=p.burn+math.floor(self:WeaponCount(3)/2)*4
        if burn>0 then e.burnTime=3 e.burnDamage=burn end
    end
    if e.hp<=0 then self:Kill(e) end
end

function Dungeon:Hurt(damage)
    local p=self.player
    if self.state~="playing" or p.invuln>0 or p.dashTime>0 then return end
    local amount=math.max(1,math.floor(damage-p.def))
    p.hp=math.max(0,p.hp-amount)
    p.invuln=0.55 p.hit=0.24
    self:Float(p.x,p.y-40,"-"..amount,{244,105,91})
    if p.hp<=0 then self:Finish(false) end
end

function Dungeon:Finish(cleared)
    if self.settled then return end
    self.settled=true
    self.state=cleared and "win" or "dead"
    self.save.runs=self.save.runs+1
    self.save.clears=self.save.clears+(cleared and 1 or 0)
    self.save.kills=self.save.kills+self.kills
    self.save.gold=self.save.gold+self.gold
    self.save.bestFloor=math.max(self.save.bestFloor,self.floor)
    self.save.bestWave=math.max(self.save.bestWave,self.wave)
    self.saveDirty=true
end



function Dungeon:Nearest(range)
    local target=false
    local best=range
    for _,e in ipairs(self.enemies) do
        local d=distance(self.player,e)-e.r
        if Feel.Ready(e) and d<=best and self:WallFraction(self.player.x,self.player.y,e.x,e.y,2)>=1 then
            target=e best=d
        end
    end
    return target
end

-- Fraction of the swept segment before the first blocked sample (step <= 4px).
function Dungeon:WallFraction(x1,y1,x2,y2,r)
    local steps=math.max(1,math.ceil(math.sqrt((x2-x1)^2+(y2-y1)^2)/4))
    for i=1,steps do
        local t=i/steps
        if self:HitsWall(x1+(x2-x1)*t,y1+(y2-y1)*t,r) then return (i-1)/steps end
    end
    return 1
end

local function segmentHit(x1,y1,x2,y2,e,r)
    local dx,dy=x2-x1,y2-y1
    local a=dx*dx+dy*dy
    local ox,oy=x1-e.x,y1-e.y
    local c=ox*ox+oy*oy-(e.r+r)^2
    if c<=0 then return 0 end
    if a<0.0001 then return false end
    local b=2*(ox*dx+oy*dy)
    local disc=b*b-4*a*c
    if disc<0 then return false end
    local t=(-b-math.sqrt(disc))/(2*a)
    return t>=0 and t<=1 and t or false
end

function Dungeon:Shoot(kind,angle,damage,pierce)
    local p=self.player
    local speed=kind=="arrow" and 690 or kind=="fireball" and 370 or 530
    self.shots[#self.shots+1]={x=p.x,y=p.y,vx=math.cos(angle)*speed,vy=math.sin(angle)*speed,
        kind=kind,originKind=kind=="arrow" and 2 or kind=="fireball" and 3 or 1,bounces=0,
        damage=damage,r=kind=="fireball" and 9 or 4,life=1.3,hits={},remaining=kind=="arrow" and (pierce or 2) or kind=="blade" and 6 or 1,enemy=false}
end

function Dungeon:Attack(angle,slot)
    local p=self.player
    local w=slot or self.loadout[1]
    if not w then return end
    local stats=self:WeaponStats(w)
    p.aim=angle w.angle=angle
    if w.kind==1 then
        Feel.Sword(self,w,angle,stats)
    else self:Shoot(w.kind==2 and "arrow" or "fireball",angle,stats.damage,stats.pierce) end
    WeaponEvolutions.AfterAttack(self,w,stats)
    w.cd=stats.cooldown
    p.attackCd=stats.cooldown
end

function Dungeon:Cast(skill)
    if self.state~="playing" then return end
    local p=self.player
    if skill=="burst" then
        Director.Ignite(self)
    elseif skill=="potion" then
        if p.potions<=0 or p.hp>=p.maxHp then return end
        p.potions=p.potions-1 p.hp=math.min(p.maxHp,p.hp+p.maxHp*0.45)
        self:Effect(p.x,p.y,50,"heal")
    elseif skill=="dash" and p.dashCd<=0 then
        p.dashTime=0.17 p.dashCd=1.2 p.invuln=0.3
    elseif skill=="whirl" and p.whirlCd<=0 then
        p.whirlCd=5 p.invuln=math.max(p.invuln,0.6)
        self:Effect(p.x,p.y,145,"whirl")
        for _,e in ipairs(self.enemies) do
            if not e.dead and distance(p,e)<145+e.r and self:WallFraction(p.x,p.y,e.x,e.y,2)>=1 then
                self:DamageEnemy(e,p.atk*2.4,true)
            end
        end
    elseif skill=="blade" and p.bladeCd<=0 then
        p.bladeCd=6 self:Shoot("blade",p.aim,p.atk*2.2)
    end
    self:PresentTalent()
end

function Dungeon:UpdateShots(dt)
    for i=#self.shots,1,-1 do
        local shot=self.shots[i]
        local x,y=shot.x,shot.y
        local nx,ny=x+shot.vx*dt,y+shot.vy*dt
        local wall=self:WallFraction(x,y,nx,ny,shot.r)
        local hits={}
        if shot.enemy then
            local t=segmentHit(x,y,nx,ny,self.player,shot.r)
            if t and t<=wall then self:Hurt(shot.damage) shot.life=0 end
        else
            for _,e in ipairs(self.enemies) do
                if Feel.Ready(e) and not shot.hits[e] then
                    local t=segmentHit(x,y,nx,ny,e,shot.r)
                    if t and t<=wall then hits[#hits+1]={t=t,enemy=e} end
                end
            end
            table.sort(hits,function(a,b) return a.t<b.t end)
            for _,hit in ipairs(hits) do
                if shot.remaining<=0 then break end
                if not hit.enemy.dead then
                    shot.hits[hit.enemy]=true
                    self:DamageEnemy(hit.enemy,shot.damage,true,{x=x,y=y,knockback=shot.kind=="fireball" and 46 or 24})
                    shot.remaining=shot.remaining-1
                    if shot.kind=="fireball" then
                        local bx,by=x+(nx-x)*hit.t,y+(ny-y)*hit.t
                        self:Effect(bx,by,72,"fire")
                        for _,e in ipairs(self.enemies) do
                            if e~=hit.enemy and not e.dead and distance({x=bx,y=by},e)<72+e.r and self:WallFraction(bx,by,e.x,e.y,2)>=1 then
                                self:DamageEnemy(e,shot.damage*0.65,true)
                            end
                        end
                    end
                    if shot.kind=="arrow" then
                        local bx,by=x+(nx-x)*hit.t,y+(ny-y)*hit.t
                        if WeaponEvolutions.Bounce(self,shot,hit.enemy,bx,by) then
                            -- A ricochet starts at the exact contact point. The
                            -- old segment's remaining hits and wall no longer
                            -- describe its direction; sweep the new ray next frame.
                            nx,ny=shot.x,shot.y wall=1
                            break
                        end
                    end
                end
            end
        end
        shot.x=nx shot.y=ny shot.life=shot.life-dt
        if wall<1 or shot.life<=0 or shot.remaining<=0 then table.remove(self.shots,i) end
    end
end

function Dungeon:UpdateEnemy(e,dt)
    if e.dead then return end
    -- Keep the lock for the entire update, including the frame that a charge
    -- ends, so the later crowd separation cannot move its final contact point.
    e.laneLocked=hunterLocked(e)
    e.hit=math.max(0,e.hit-dt) e.born=e.born+dt
    if e.burnTime>0 then
        local active=math.min(dt,e.burnTime)
        e.hp=e.hp-e.burnDamage*active
        -- A kill on the last valid burning frame still carries the flame.
        if e.hp<=0 then self:Kill(e) return end
        e.burnTime=math.max(0,e.burnTime-dt)
    end
    if e.born<0.5 then return end
    if e.laneLocked then e.kickX=0 e.kickY=0
    else
        self:Move(e,e.kickX*dt,e.kickY*dt)
        e.kickX=e.kickX*math.exp(-12*dt) e.kickY=e.kickY*math.exp(-12*dt)
    end
    e.stagger=math.max(0,e.stagger-dt)
    if e.stagger>0 and not (e.kind=="hunter" and (e.windup>0 or e.charge>0)) then return end
    local p=self.player
    local d=distance(e,p)
    local a=math.atan(p.y-e.y,p.x-e.x)
    if e.bounty then a=a+math.pi+math.sin(e.born*5)*0.3 end
    local speed=e.speed
    if not e.bounty and e.kind=="bat" then
        -- A light weaving flanker; the silhouette and wingbeat identify it.
        a=a+math.sin(e.born*5.2)*0.42
    elseif e.kind=="skeleton" and d>90 then
        -- Short lead cuts across a circular escape without homing a dash.
        a=math.atan(p.y+p.vy*0.18-e.y,p.x+p.vx*0.18-e.x)
    end
    if e.kind=="hunter" then
        e.bossCd=e.bossCd-dt
        if e.windup>0 then
            e.windup=e.windup-dt
            if e.windup<=0 then e.charge=0.42 end
            return
        elseif e.charge>0 then
            local travelTime=math.min(dt,e.charge)
            local travel=math.min(560*travelTime,e.chargeDistance)
            e.x=e.x+e.chargeX*travel e.y=e.y+e.chargeY*travel
            e.chargeDistance=math.max(0,e.chargeDistance-travel)
            e.charge=math.max(0,e.charge-dt)
            if e.chargeDistance<=0.0001 then e.charge=0 end
            if distance(e,p)<e.r+p.r+4 then self:Hurt(e.atk) end
            return
        elseif e.bossCd<=0 and d<460 then
            local tx=clamp(p.x+p.vx*0.62,65,895)
            local ty=clamp(p.y+p.vy*0.62,113,511)
            local aim=math.atan(ty-e.y,tx-e.x)
            e.chargeX=math.cos(aim) e.chargeY=math.sin(aim)
            -- Use exactly the straight segment shown by the warning. Axis-wise
            -- actor sliding would bend the dash around a pillar after impact.
            local reach=560*0.42
            e.chargeDistance=reach*self:WallFraction(e.x,e.y,
                e.x+e.chargeX*reach,e.y+e.chargeY*reach,e.r)
            e.laneLocked=true e.kickX=0 e.kickY=0
            e.windup=0.65 e.bossCd=3.6
            return
        end
    end
    if e.kind=="boss" then
        e.bossCd=e.bossCd-dt
        if e.windup>0 then
            e.windup=e.windup-dt
            if e.windup<=0 then e.charge=0.55 end
            return
        elseif e.charge>0 then
            e.charge=e.charge-dt
            self:Move(e,e.chargeX*420*dt,e.chargeY*420*dt)
            if distance(e,p)<e.r+p.r+7 then self:Hurt(e.atk*1.4) end
            return
        elseif e.bossCd<=0 then
            e.bossCd=e.hp<e.maxHp/2 and 2.3 or 3.5
            e.windup=0.85 e.chargeX=math.cos(a) e.chargeY=math.sin(a)
            return
        end
    end
    if e.kind=="mage" then
        e.shootCd=e.shootCd-dt
        if e.shootCd<=0 and self:WallFraction(e.x,e.y,p.x,p.y,3)>=1 then
            e.shootCd=1.7
            self.hazards[#self.hazards+1]={x=p.x,y=p.y,r=38,time=0.9,damage=e.atk*1.5}
            local fan=self.wave>=5 and 1 or 0
            for i=-fan,fan do
                local aim=a+i*0.24
                self.shots[#self.shots+1]={x=e.x,y=e.y,vx=math.cos(aim)*215,vy=math.sin(aim)*215,r=6,
                    life=3,damage=e.atk,enemy=true,kind="hex",remaining=1,hits={}}
            end
        end
        if d<165 then a=a+math.pi
        elseif d<285 then a=a+math.pi/2 speed=speed*0.6 end
    end
    if e.bounty or d>e.r+p.r+3 then
        for _,offset in ipairs({0,0.6,-0.6,1.2,-1.2,1.8,-1.8}) do
            local dx,dy=math.cos(a+offset),math.sin(a+offset)
            if not self:HitsWall(e.x+dx*22,e.y+dy*22,e.r) then self:Move(e,dx*speed*dt,dy*speed*dt) break end
        end
    else
        e.attackCd=e.attackCd-dt
        if e.attackCd<=0 then e.attackCd=0.8 self:Hurt(e.atk) end
    end
end

function Dungeon:Update(dt,mx,my)
    self.time=self.time+dt
    if self.state~="playing" then return end
    dt=math.min(dt,0.034)
    self.runTime=self.runTime+dt
    self.bannerTime=math.max(0,self.bannerTime-dt)
    local p=self.player
    local previousX,previousY=p.x,p.y
    for _,key in ipairs({"attackCd","invuln","dashCd","whirlCd","bladeCd","hit"}) do p[key]=math.max(0,p[key]-dt) end
    local length=math.sqrt(mx*mx+my*my)
    p.moving=length>0.1
    if p.moving then
        mx=mx/math.max(1,length) my=my/math.max(1,length)
        local moveLength=math.max(0.001,math.sqrt(mx*mx+my*my))
        p.dashX=mx/moveLength p.dashY=my/moveLength
        p.aim=math.atan(my,mx) p.walk=p.walk+dt*10
    end
    if p.dashTime>0 then
        p.dashTime=math.max(0,p.dashTime-dt)
        self:Move(p,p.dashX*720*dt,p.dashY*720*dt)
    else self:Move(p,mx*p.speed*dt,my*p.speed*dt) end
    p.vx=(p.x-previousX)/math.max(0.001,dt) p.vy=(p.y-previousY)/math.max(0.001,dt)
    for _,w in ipairs(self.loadout) do
        w.cd=math.max(0,w.cd-dt)
        if w.cd<=0 then
            local target=self:Nearest(self:WeaponStats(w).targetRange)
            if target then self:Attack(math.atan(target.y-p.y,target.x-p.x),w) end
        end
    end
    Feel.UpdateSwords(self,dt)
    for _,e in ipairs(self.enemies) do self:UpdateEnemy(e,dt) if self.state~="playing" then return end end
    -- Resolve circle overlap after AI. A dense crowd keeps physical spacing,
    -- instead of collapsing into one point that a single slash deletes.
    for i=1,#self.enemies do
        local a=self.enemies[i]
        if not a.dead then
            for j=i+1,#self.enemies do
                local b=self.enemies[j]
                if not b.dead then
                    local dx,dy=b.x-a.x,b.y-a.y
                    local d=math.sqrt(dx*dx+dy*dy)
                    local gap=a.r+b.r+2
                    if d<gap then
                        local nx,ny=1,0
                        if d>0.001 then nx=dx/d ny=dy/d end
                        local push=math.min((gap-d)*0.5,110*dt)
                        if not a.laneLocked then self:Move(a,-nx*push,-ny*push) end
                        if not b.laneLocked then self:Move(b,nx*push,ny*push) end
                    end
                end
            end
        end
    end
    for i=#self.hazards,1,-1 do
        local hazard=self.hazards[i] hazard.time=hazard.time-dt
        if hazard.time<=0 then
            if (p.x-hazard.x)^2+(p.y-hazard.y)^2<(hazard.r+p.r)^2 then self:Hurt(hazard.damage) end
            self:Effect(hazard.x,hazard.y,hazard.r,"fire")
            table.remove(self.hazards,i)
        end
    end
    self:UpdateShots(dt)
    if self.state~="playing" then return end
    -- Defer structural removal until all recursive damage callbacks finish.
    for i=#self.enemies,1,-1 do if self.enemies[i].dead then table.remove(self.enemies,i) end end
    for i=#self.effects,1,-1 do
        local e=self.effects[i] e.life=e.life-dt
        if e.life<=0 then table.remove(self.effects,i) end
    end
    for i=#self.floats,1,-1 do
        local f=self.floats[i] f.life=f.life-dt f.y=f.y-30*dt
        if f.life<=0 then table.remove(self.floats,i) end
    end
    Feel.Update(self,dt)
    Survival.Frame(self,dt)
end

return Dungeon
