-- Short combat beats and visible build changes. No engine dependencies.
local Director={}
Director.Waves={
    "骷髅潮", "蝠群突袭", "法师交叉火力", "重装围猎",
    "追击与封锁", "暗影军团", "最后的围城", "首领决战",
}

---@param g table
function Director.Init(g)
    g.overdriveTime=0 g.frenzyCharge=0 g.hitCount=0
    g.bountySpawned=false g.bountyKills=0
    g.formationBeat=0 g.burstCount=0
    g.burstRecovery=0 g.forgeVouchers=0 g.forgeClaimed=0 g.burstImmediateKills=0
end

---@param g table
function Director.Kill(g,e)
    if g.overdriveTime<=0 then
        local before=g.frenzyCharge
        g.frenzyCharge=math.min(8,g.frenzyCharge+(e.bounty and 4 or e.elite and 3 or 1))
        if before<8 and g.frenzyCharge>=8 then
            g:Banner(g.burstRecovery>0 and "引燃能量已满 · 等待恢复" or "狂热就绪 · 按 E 引燃，留给密集敌群")
        end
    end
    if e.bounty then g.bountyKills=g.bountyKills+1 g:Banner("夺宝成功 · 拾取金色宝箱") end
end

---@param g table
function Director.Ignite(g)
    if g.state~="playing" or g.frenzyCharge<8 or g.burstRecovery>0 then return false end
    g.frenzyCharge=0 g.overdriveTime=2 g.burstRecovery=9 g.burstCount=g.burstCount+1
    g:Banner("狂热引燃 · 清场冲击与2秒强化")
    g:Effect(g.player.x,g.player.y,155,"burst")
    g.shake=math.max(g.shake,2)
    local before=g.kills
    Director.Blast(g,g.player.x,g.player.y,150,g.player.atk*2.4,false)
    g.burstImmediateKills=g.burstImmediateKills+g.kills-before
    return true
end

---@param g table
function Director.Blast(g,x,y,r,damage,exclude)
    g:Effect(x,y,r,"fire")
    for _,e in ipairs(g.enemies) do
        if e~=exclude and not e.dead and e.born>=0.5 and (e.x-x)^2+(e.y-y)^2<=(r+e.r)^2
            and g:WallFraction(x,y,e.x,e.y,2)>=1 then
            g:DamageEnemy(e,damage,false,{x=x,y=y,knockback=36})
        end
    end
end

local function living(g)
    local n=0 for _,e in ipairs(g.enemies) do if not e.dead then n=n+1 end end
    return n
end

---@param g table
function Director.Formation(g)
    local n=math.min(7+math.floor(g.wave/2),64-living(g))
    local angle=math.random()*math.pi*2
    local decks={
        {"skeleton","bat","skeleton"},
        {"hunter","bat","bat","skeleton"},
        {"mage","skeleton","hunter","bat"},
        {"zombie","skeleton","hunter","bat","mage"},
        {"hunter","zombie","mage","bat","skeleton"},
    }
    local deck=decks[math.min(g.wave,#decks)]
    for i=1,n do
        -- Approach as an arc with an escape side, rather than a full surround.
        local a=angle+(i-(n+1)/2)*0.22
        local radius=205+(i%2)*40
        local x,y=g.player.x+math.cos(a)*radius,g.player.y+math.sin(a)*radius
        local clear=not g:HitsWall(x,y,24)
        for _,e in ipairs(g.enemies) do
            if not e.dead and (e.x-x)^2+(e.y-y)^2<(e.r+23)^2 then clear=false break end
        end
        if clear then
            local kind=deck[(i-1)%#deck+1]
            local specials=0
            if kind=="hunter" or kind=="mage" then
                for _,e in ipairs(g.enemies) do if not e.dead and e.kind==kind then specials=specials+1 end end
                if specials>=math.min(4,2+math.floor(g.wave/3)) then kind="skeleton" end
            end
            g:SpawnEnemy(kind,x,y,false).born=-0.25
        end
    end
    g:Banner(Director.Waves[g.wave]..(g.wave>=2 and " · 猎手蓄力时转向或翻滚" or " · 敌群压境"))
end

---@param g table
function Director.BeginWave(g)
    g.bountySpawned=false g.formationBeat=0 g.overdriveTime=0 g.frenzyCharge=0 g.burstRecovery=0
    -- The first encounter enters weapon reach quickly instead of leaving an
    -- empty arena while distant random enemies slowly walk in.
    if g.wave==1 then
        for i=1,5 do
            local a=math.pi+(i-1)*math.pi/4
            local x,y=g.player.x+math.cos(a)*155,g.player.y+math.sin(a)*155
            if not g:HitsWall(x,y,20) then g:SpawnEnemy("skeleton",x,y,false).born=-0.25 end
        end
    end
end

---@param g table
function Director.Frame(g,dt)
    g.overdriveTime=math.max(0,g.overdriveTime-dt)
    local recovery=g.burstRecovery
    g.burstRecovery=math.max(0,g.burstRecovery-dt)
    if recovery>0 and g.burstRecovery<=0 and g.frenzyCharge>=8 then
        g:Banner("狂热就绪 · 按 E 引燃，留给密集敌群")
    end
    local elapsed=g.waveDuration-g.waveTime
    if not g.bountySpawned and elapsed>=6 then
        g.bountySpawned=true
        local x,y=g:FreeSpot()
        local e=g:SpawnEnemy("bat",x,y,false)
        e.bounty=true e.escapeTime=11 e.speed=105 e.hp=24+g.wave*5 e.maxHp=e.hp e.xp=20 e.born=-0.25
        g:Banner("携宝怪出现 · 拾取宝箱可免费自选武器，波末消失")
    end
    local beat=elapsed>=14 and 2 or elapsed>=4 and 1 or 0
    if beat>g.formationBeat then g.formationBeat=beat Director.Formation(g) end
    for _,e in ipairs(g.enemies) do
        if e.bounty and not e.dead then
            e.escapeTime=e.escapeTime-dt
            if e.escapeTime<=0 then e.dead=true g:Banner("携宝怪逃走了 · 下一波还有机会") end
        end
    end
end

return Director
