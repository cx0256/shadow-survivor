-- Optional map objectives. Combat and wave-end economy remain in Survival.
---@class CombatTrialsAPI
---@field Init fun(g: table)
---@field BeginWave fun(g: table)
---@field CompletedBounty fun(g: table, item: table): boolean
---@field CanExit fun(g: table): boolean
---@field RequestExit fun(g: table): boolean
---@field Frame fun(g: table, dt: number)
---@field Status fun(g: table): string
local Trials={}
function Trials.Init(g)
    g.trial={} g.trialWins=0 g.trialTimeSaved=0 g.lastTrial=nil
end
function Trials.BeginWave(g)
    g.trial={kind=g.wave%2==0 and "rift" or "bounty",
        state=g.wave>=8 and "inactive" or "waiting",r=62,progress=0,required=2.6,remaining=12}
end
local function complete(g,x,y)
    local t=g.trial
    t.state="won" t.exit={x=x,y=y,r=30,departing=false,used=false,progress=0}
    g.trialWins=g.trialWins+1
    g.lastTrial={wave=g.wave,kind=t.kind,time=g.runTime}
    g:Banner("目标完成 · 捷径开启；也可留下继续收集")
end
local function insideGate(g,gate)
    return (g.player.x-gate.x)^2+(g.player.y-gate.y)^2<=gate.r^2
end
function Trials.CanExit(g)
    local gate=g.trial and g.trial.exit
    return g.state=="playing" and g.waveActive and g.waveTime>0 and gate~=nil
        and not gate.used and not gate.departing and insideGate(g,gate)
end
function Trials.RequestExit(g)
    if not Trials.CanExit(g) then return false end
    g.trial.exit.departing=true
    return true
end
function Trials.CompletedBounty(g,item)
    local t=g.trial
    if g.state~="playing" or not g.waveActive or g.waveTime<=0 or g.wave>=8
        or not t or t.kind~="bounty" or t.state=="won"
        or not item.treasure or not item.collected then return false end
    complete(g,item.x,item.y)
    return true
end
local function activate(g,t)
    local candidates={}
    for y=170,450,70 do for x=130,830,70 do
        if not g:HitsWall(x,y,t.r) and (x-g.player.x)^2+(y-g.player.y)^2>=140^2 then
            candidates[#candidates+1]={x=x,y=y}
        end
    end end
    if #candidates==0 then t.state="expired" return end
    local spot=candidates[math.random(#candidates)]
    t.x=spot.x t.y=spot.y t.state="active"
    local living=0 for _,e in ipairs(g.enemies) do if not e.dead then living=living+1 end end
    local a=math.atan(t.y-g.player.y,t.x-g.player.x)
    for i=1,math.min(3,64-living) do
        local angle=a+(i-2)*0.4
        local x,y=t.x+math.cos(angle)*100,t.y+math.sin(angle)*100
        local clear=not g:HitsWall(x,y,24) and (x-g.player.x)^2+(y-g.player.y)^2>=140^2
        for _,e in ipairs(g.enemies) do
            if not e.dead and (x-e.x)^2+(y-e.y)^2<(e.r+24)^2 then clear=false break end
        end
        if clear then g:SpawnEnemy(i==2 and "bat" or "skeleton",x,y,false).born=-0.25 end
    end
    g:Banner("裂隙开启 · 12秒内守圈2.6秒，赢取锻造券")
end
function Trials.Frame(g,dt)
    if g.state~="playing" or not g.waveActive or g.waveTime<=0 then return end
    local t=g.trial
    if not t or t.state=="inactive" then return end
    if t.kind=="rift" and t.state=="waiting" and g.waveDuration-g.waveTime>=4 then activate(g,t) end
    if t.state=="active" then
        local active=math.min(dt,t.remaining)
        local inside=(g.player.x-t.x)^2+(g.player.y-t.y)^2<=t.r^2
        t.progress=math.max(0,math.min(t.required,t.progress+(inside and active or -active*0.55)))
        t.remaining=math.max(0,t.remaining-dt)
        if t.progress>=t.required-0.000001 then
            g.forgeVouchers=g.forgeVouchers+1
            local reward=8+g.wave*2
            g:AddGold(reward) g.waveIncome=g.waveIncome+reward
            g.player.hp=math.min(g.player.maxHp,g.player.hp+12) g.frenzyCharge=8
            complete(g,t.x,t.y)
            g:Effect(t.x,t.y,160,"counter")
            for _,e in ipairs(g.enemies) do
                if not e.dead and e.born>=0.5 and (e.x-t.x)^2+(e.y-t.y)^2<=(160+e.r)^2
                    and g:WallFraction(t.x,t.y,e.x,e.y,2)>=1 then
                    g:DamageEnemy(e,g.player.atk*2.4,false,{x=t.x,y=t.y,knockback=36})
                end
            end
        elseif t.remaining<=0 then t.state="expired" g:Banner("裂隙消散 · 继续生存仍可过关") end
    end
    local gate=t.exit
    if gate and gate.departing and not gate.used then
        if insideGate(g,gate) then
            gate.progress=gate.progress+dt
            if gate.progress>=0.6 then
                gate.used=true g.trialTimeSaved=g.trialTimeSaved+g.waveTime g.waveTime=0
            end
        else gate.departing=false gate.progress=0 end
    end
end
function Trials.Status(g)
    local t=g.trial
    if not t or t.state=="inactive" then return "决战 · 击败首领或坚持到时限" end
    if t.exit then
        if t.exit.departing then return "正在撤离 · 留在圈内" end
        local instruction=Trials.CanExit(g) and "可撤离，也可继续战斗" or "进入撤离圈，可提前结束本波"
        for _,drop in ipairs(g.drops) do
            if drop.treasure and not drop.collected then return instruction.."\n撤离前记得拾取宝箱" end
        end
        return instruction.."\n也可留下继续收集"
    end
    if t.state=="active" then return string.format("守圈 %.1f / 2.6秒\n裂隙剩余 %d秒",t.progress,math.ceil(t.remaining)) end
    if t.state=="expired" then return "裂隙已消散 · 坚持生存" end
    return t.kind=="rift" and "本波目标：守住绿色裂隙" or "本波目标：追宝并拾取宝箱"
end
return Trials
