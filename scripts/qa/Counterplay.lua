-- Pure Lua combat checks: real roll collisions and weapon payloads, no engine.
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type CombatFeelAPI
local Feel=require "CombatFeel"
local passed=0
local function check(ok,message) assert(ok,message) passed=passed+1 end
local function close(a,b) return math.abs(a-b)<0.00001 end
local function game(kind)
    local g=Dungeon.New({}) g:SetWeapon(kind or 1) g:Start()
    g.enemies={} g.shots={} g.hazards={} g.loadout={}
    g.spawnTimer=999 g.bountySpawned=true g.formationBeat=2
    g.player.x=400 g.player.y=300 g.player.crit=0 g.player.invuln=0
    return g
end
local function tick(g,seconds)
    while seconds>0 do
        local dt=math.min(seconds,0.02) g:Update(dt,0,0) seconds=seconds-dt
    end
end
local function earn(g)
    g:Cast("dash") g:Hurt(20)
end

local g=game()
local hp=g.player.hp
earn(g)
check(g.player.hp==hp and g.perfectDodges==1 and close(g.counterTime,2),
    "an actual hit intercepted by a roll grants two seconds of counterattack without damage")
check(close(g.counterRecovery,3),"a perfect dodge begins a three-second recovery")
g:Hurt(20) g:Hurt(20)
check(g.perfectDodges==1 and close(g.counterTime,2),"overlapping hits reward a roll only once")
-- Isolate the per-roll guard from the independent recovery timer.
g.counterRecovery=0 g:Hurt(20)
check(g.perfectDodges==1,"the same roll cannot earn another reward even after recovery is cleared")

g=game() earn(g) tick(g,1.3)
g:Cast("dash") g:Hurt(20)
check(g.perfectDodges==1 and g.counterRecovery>0 and g.player.hp==g.player.maxHp,
    "a new roll remains safe but cannot reward again during recovery")
tick(g,1.8) g:Cast("dash") g:Hurt(20)
check(g.perfectDodges==2 and close(g.counterTime,2),
    "another real roll can earn a fresh counter after three seconds")

g=game() g:Cast("dash") tick(g,0.4)
check(g.perfectDodges==0 and g.counterTime==0,"an empty roll never awards a counterattack")
g=game() g.player.invuln=1 g:Hurt(20)
check(g.perfectDodges==0 and g.counterTime==0 and g.player.hp==g.player.maxHp,
    "ordinary damage immunity does not count as a perfect dodge")
g=game() g:Cast("dash") g:Hurt(0)
check(g.perfectDodges==0 and g.counterTime==0,"zero damage cannot farm perfect dodges")
g.state="paused" g:Hurt(20)
check(g.perfectDodges==0 and g.counterTime==0,"paused combat cannot award perfect dodges")

g=game() earn(g)
local duration,recovery,dash=g.counterTime,g.counterRecovery,g.player.dashTime
g.state="paused" g:Update(5,1,0)
check(g.counterTime==duration and g.counterRecovery==recovery and g.player.dashTime==dash,
    "pause freezes both the counter window and roll recovery")
g.state="playing" tick(g,2.01)
check(g.counterTime==0 and g.counterRecovery>0,"an unused counter expires after two seconds of combat")
local w={kind=2,tier=1,cd=0,angle=0}
local base=g:WeaponStats(w).damage g:Attack(0,w)
check(close(g.shots[1].damage,base),"an expired counter cannot strengthen a later projectile")

for kind=1,3 do
    g=game(kind)
    w={kind=kind,tier=1,cd=0,angle=0} g.loadout={w}
    local stats=g:WeaponStats(w)
    local target=g:SpawnEnemy("zombie",480,300,false)
    earn(g)
    check(close(g:WeaponStats(w).damage,stats.damage),
        "counter readiness does not change displayed or persistent weapon stats: "..kind)
    g:Attack(0,w)
    local payload=kind==1 and g.melee[1] or g.shots[1]
    check(close(payload.damage,stats.damage*1.8) and g.counterTime==0,
        "next actual sword/arrow/fireball carries one 1.8x counter: "..kind)
    if kind==1 then
        for _=1,30 do Feel.UpdateSwords(g,0.01) end
    else g:UpdateShots(0.3) end
    check(target.maxHp-target.hp==math.floor(stats.damage*1.8),
        "counter payload reaches the enemy through real weapon collision: "..kind)
    check(close(g:WeaponStats(w).damage,stats.damage) and close(g:WeaponStats(w).cooldown,stats.cooldown),
        "consuming a counter does not permanently mutate weapon stats: "..kind)
    g.melee={} g.shots={} w.swing=false
    g:Attack(0,w)
    payload=kind==1 and g.melee[1] or g.shots[1]
    check(close(payload.damage,stats.damage),"the following weapon attack has ordinary damage: "..kind)
end

g=game() earn(g) g:Attack(0)
check(close(g.counterTime,2),"an absent weapon cannot spend the pending counter")
g.loadout={{kind=2,tier=1,cd=0,angle=0},{kind=3,tier=1,cd=0,angle=0}}
local first,second=g:WeaponStats(g.loadout[1]).damage,g:WeaponStats(g.loadout[2]).damage
g:Attack(0,g.loadout[1]) g:Attack(0,g.loadout[2])
check(close(g.shots[1].damage,first*1.8) and close(g.shots[2].damage,second),
    "simultaneous weapon slots share one counter instead of multiplying its reward")

-- The hazard resolves after movement has exhausted the final dash slice.
g=game() g:Cast("dash")
g.player.dashTime=0.01 g.player.dashX=1 g.player.dashY=0
g.hazards={{x=g.player.x+720*0.02,y=g.player.y,r=10,time=0.01,damage=20}}
g:Update(0.02,0,0)
check(g.player.dashTime==0 and g.player.dashingThisFrame and g.perfectDodges==1,
    "a real hazard on the roll's last movement frame still rewards the dodge")
check(g.player.hp==g.player.maxHp and #g.hazards==0,"last-frame hazard is consumed without hurting the rolling player")
g:Update(0.02,0,0) g.player.invuln=0 hp=g.player.hp g:Hurt(20)
check(not g.player.dashingThisFrame and g.player.hp<hp and g.perfectDodges==1,
    "the expired last-frame flag cannot grant ongoing immunity or extra rewards")

g=game() earn(g) g.waveTime=0.001 g:Update(0.02,0,0)

check(g.state=="shop" and g.counterTime==0,"the wave-end shop discards unspent counterattack power")
check(g:BeginWave() and g.counterTime==0 and g.counterRecovery==0
    and g.player.dashTime==0 and not g.player.dashingThisFrame and not g.player.dashRewarded,
    "the next wave clears combat-only dodge and counter state")
check(g.perfectDodges==1,"wave changes preserve the run's perfect-dodge total")
g:Start()
check(g.perfectDodges==0 and g.counterTime==0 and g.counterRecovery==0 and g.counterFlash==0,
    "restarting clears all counter progress and feedback")

print("[Counterplay] "..passed.." dodge and real counterattack checks passed")
return passed
