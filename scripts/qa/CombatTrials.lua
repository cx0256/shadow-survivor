-- Engine-independent objective regressions using real combat/economy objects.
-- No injected wins, native UI, live save, or assertions about player enjoyment.
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type SurvivorRulesAPI
local Survival=require "Survival"
---@type CombatTrialsAPI
local Trials=require "CombatTrials"
local passed=0
local function check(value,message) assert(value,message) passed=passed+1 end
local function close(a,b) return math.abs(a-b)<0.00001 end
local function game(wave)
    local g=Dungeon.New({}) g:Start()
    g.wave=wave or 2 g.waveDuration=Survival.Durations[g.wave] g.waveTime=g.waveDuration
    g.enemies={} g.drops={} g.spawnTimer=999
    Trials.Init(g) Trials.BeginWave(g)
    return g
end
local function advance(g,seconds)
    while seconds>0.000001 do
        local dt=math.min(0.034,seconds)
        Trials.Frame(g,dt) seconds=seconds-dt
    end
end
local function activate(g)
    g.waveTime=g.waveDuration-4
    Trials.Frame(g,0)
    assert(g.trial.state=="active","rift fixture activates on the real schedule")
    g.enemies={} -- isolate objective rewards from optional completion blast kills
end
local function capture(g)
    activate(g)
    g.player.x=g.trial.x g.player.y=g.trial.y
    advance(g,2.61)
    assert(g.trial.state=="won","capture fixture wins after holding the real objective")
end

local g=game(2)
check(g.trial.kind=="rift" and g.trial.state=="waiting" and not g.trial.exit,
    "even waves announce a pending rift without an early exit")
g.waveTime=g.waveDuration-3.99 Trials.Frame(g,0)
check(g.trial.state=="waiting","rift cannot activate before the four-second beat")
activate(g)
check(g.trial.progress==0 and close(g.trial.remaining,12),"activation starts a fresh twelve-second capture window")
g.player.x=g.trial.x g.player.y=g.trial.y
advance(g,1)
check(close(g.trial.progress,1),"standing inside the objective accumulates capture time")
g.player.x=g.trial.x+80
advance(g,1)
check(close(g.trial.progress,0.45),"leaving decays capture progress without abruptly resetting it")
advance(g,1)
check(g.trial.progress==0,"capture decay cannot create negative progress")
g.player.x=g.trial.x g.player.y=g.trial.y
g.player.hp=50 g.burstRecovery=4 g.frenzyCharge=2
local gold,income=g.gold,g.waveIncome
advance(g,2.61)
check(g.trial.state=="won" and g.trialWins==1 and g.forgeVouchers==1,
    "successful capture awards one forge voucher and one objective completion")
check(g.gold==gold+12 and g.waveIncome==income+12,"rift materials enter both the wallet and wave income")
check(g.player.hp==62 and g.frenzyCharge==8 and g.burstRecovery==4,
    "rift heals twelve and fills energy without bypassing burst recovery")
check(g.lastTrial and g.lastTrial.wave==2 and g.lastTrial.kind=="rift",
    "completion records the actual wave and objective kind")
local exit=g.trial.exit
check(exit and not exit.departing and not exit.used and g.waveTime>0 and Trials.CanExit(g),
    "winning opens an optional exit without ending combat under the player")
check(Trials.Status(g):find("继续战斗",1,true)~=nil,"exit instructions present the choice to stay")
gold=g.gold income=g.waveIncome
advance(g,1)
check(g.gold==gold and g.waveIncome==income and g.forgeVouchers==1 and g.trialWins==1 and g.player.hp==62,
    "remaining at a completed rift cannot repeat any reward")
check(not exit.departing and g.waveTime>0,"lingering in the exit does not end the wave")
g.player.x=exit.x+31 g.player.y=exit.y
check(not Trials.CanExit(g) and not Trials.RequestExit(g),"requests from outside the ring are ignored")
g.player.x=exit.x
advance(g,0.7)
check(g.waveTime>0 and not exit.departing,"re-entering and staying without a request keeps combat active")
check(Trials.RequestExit(g) and not Trials.RequestExit(g),"one explicit request starts the countdown")
advance(g,0.3)
g.player.x=exit.x+31 Trials.Frame(g,0.034)
check(not exit.departing and exit.progress==0,"leaving the ring cancels the pending exit")
g.player.x=exit.x
check(Trials.RequestExit(g),"an interrupted exit can be requested again")
local remaining=g.waveTime
advance(g,0.3)
check(g.waveTime>0,"requesting departure does not immediately end combat")
advance(g,0.61)
check(g.waveTime==0 and close(g.trialTimeSaved,remaining),"explicit departure ends the timer and records saved combat time")
Trials.Frame(g,0.034)
check(close(g.trialTimeSaved,remaining),"repeated exit contact cannot double count time saved")

g=game(2) activate(g)
local trial=g.trial
g.player.x=trial.x g.player.y=trial.y advance(g,0.5)
local progress,time=trial.progress,trial.remaining
for _,state in ipairs({"paused","shop","talent","dead","win"}) do
    g.state=state advance(g,1)
    check(trial.progress==progress and trial.remaining==time and g.trialWins==0,
        "objective simulation is frozen outside combat: "..state)
end
g.state="playing" g.waveActive=false advance(g,1)
check(trial.progress==progress and trial.remaining==time,"inactive waves cannot progress an objective")
g.waveActive=true g.waveTime=0 advance(g,1)
check(trial.progress==progress and trial.remaining==time,"an expired wave cannot pay a last-frame objective reward")

g=game(2) activate(g)
g.player.x=g.trial.x+100 g.player.y=g.trial.y
advance(g,12.1)
check(g.trial.state=="expired" and not g.trial.exit and g.trialWins==0,
    "missing the capture window closes the optional objective without opening an exit")
check(g.forgeVouchers==0 and g.gold==0 and g.waveIncome==0,"timeout grants no objective rewards")
g.player.x=g.trial.x advance(g,3)
check(g.trial.state=="expired" and g.trialWins==0,"late arrival cannot revive an expired objective")

g=game(6) g.player.hp=g.player.maxHp-3 capture(g)
check(g.player.hp==g.player.maxHp and g.gold==20,"later-wave rewards use their current wave and healing clamps at max HP")
g.wave=7 g.waveTime=50 g.waveDuration=50 Trials.BeginWave(g)
check(g.trial.kind=="bounty" and not g.trial.exit and g.trialWins==1,
    "next wave resets transient objective and exit state while preserving run totals")
Trials.Init(g)
check(g.trialWins==0 and g.trialTimeSaved==0 and not g.lastTrial,"new runs reset objective records and saved time")

-- The actual map has two pillars. Sample seeded center, wall, and pillar-edge
-- positions so a location fallback cannot silently put the full capture ring
-- through geometry or reinforcements directly on the player.
local positions={{480,380},{80,130},{880,500},{160,312},{690,312},{480,115}}
for seed=1,8 do
    for _,position in ipairs(positions) do
        math.randomseed(20261026+seed)
        g=game(2) g.player.x=position[1] g.player.y=position[2]
        g.waveTime=g.waveDuration-4 Trials.Frame(g,0)
        trial=g.trial
        check(trial.state=="active" and not g:HitsWall(trial.x,trial.y,trial.r),
            "capture ring fits the accessible arena across seeded positions")
        check((trial.x-g.player.x)^2+(trial.y-g.player.y)^2>=140^2,
            "rift placement requires a deliberate route from the current player")
        local safe=true
        for _,enemy in ipairs(g.enemies) do
            if enemy.born~=-0.25 or g:HitsWall(enemy.x,enemy.y,enemy.r)
                or (enemy.x-g.player.x)^2+(enemy.y-g.player.y)^2<140^2 then safe=false end
        end
        check(safe and #g.enemies<=3,"rift reinforcement positions are prewarned, sparse, and outside immediate contact")
    end
end
g=game(4)
for i=1,64 do g:SpawnEnemy("skeleton",300+(i%8)*35,180+math.floor(i/8)*30,false) end
g.waveTime=g.waveDuration-4 Trials.Frame(g,0)
check(#g.enemies==64,"objective reinforcements respect the existing enemy budget")

-- A bounty is completed by collecting its real treasure, never by its death
-- or by remote credit. The normal pickup function owns the monetary reward.
g=game(1)
local bounty=g:SpawnEnemy("bat",g.player.x,g.player.y,false) bounty.bounty=true
g:Kill(bounty)
local treasure
for _,drop in ipairs(g.drops) do if drop.treasure then treasure=drop break end end
assert(treasure,"real bounty death creates a treasure")
check(not Trials.CompletedBounty(g,treasure) and g.trialWins==0 and not g.trial.exit,
    "uncollected treasure cannot open the bounty exit")
Survival.Pickup(g,treasure)
check(g.trial.state=="won" and g.trialWins==1 and g.forgeVouchers==1 and g.gold==10,
    "real bounty pickup grants its existing reward once and opens the objective exit")
check(g.trial.exit and not g.trial.exit.departing and g.waveTime>0,
    "collecting a treasure cannot immediately extract the player")
gold=g.gold
check(not Trials.CompletedBounty(g,treasure) and g.trialWins==1 and g.gold==gold and g.forgeVouchers==1,
    "repeated bounty notification cannot duplicate reward or completion")
local untouched={kind="material",treasure=true,collected=false,value=10,xp=20,x=400,y=200}
g.drops={untouched}
local guidance=Trials.Status(g)
check(guidance:find("宝箱",1,true)~=nil and guidance:find("可撤离",1,true)~=nil,
    "a remaining treasure warns the player while preserving exit instructions")
Trials.Frame(g,0.034)
check(not untouched.collected,"exit guidance never remotely collects special treasure")

for _,wave in ipairs({2,4,6,8}) do
    g=game(wave)
    local item={kind="material",treasure=true,collected=true,x=g.player.x,y=g.player.y}
    check(not Trials.CompletedBounty(g,item) and g.trialWins==0 and not g.trial.exit,
        "bounty completion cannot bypass a different objective or final boss: wave "..wave)
end
g=game(3)
local item={kind="material",treasure=true,collected=true,x=g.player.x,y=g.player.y}
g.state="paused"
check(not Trials.CompletedBounty(g,item),"paused state cannot complete a bounty")
g.state="playing" g.waveActive=false
check(not Trials.CompletedBounty(g,item),"inactive combat cannot complete a bounty")
g.waveActive=true item.treasure=false
check(not Trials.CompletedBounty(g,item),"ordinary material pickup cannot complete a bounty")
item.treasure=true
check(Trials.CompletedBounty(g,item) and g.forgeVouchers==0 and g.gold==0,
    "bounty objective callback itself does not grant a second material or voucher reward")

g=game(8) g.waveTime=1 Trials.Frame(g,0.034)
check(g.trial.state=="inactive" and not g.trial.exit and g.waveTime==1,
    "final boss wave has no objective exit or timer bypass")
print("[CombatTrialChecks] "..passed.." passed")
return passed
