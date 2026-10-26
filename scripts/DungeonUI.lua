-- Native Maker UI: shared theme, fixed menu actions, bounded combat HUD.
local UI=require "urhox-libs/UI"
local T=require "DungeonTheme"
local Screens=require "DungeonScreens"
local HUD={}
HUD.__index=HUD
local C=T.C

function HUD.New(game)
    local self=setmetatable({},HUD)
    self:Init(game)
    return self
end

function HUD:Init(game)
    self.game=game self.lastState="" self.lastChoice="" self.message=""
    self.compact=UI.GetWidth()<600
    local small=self.compact
    self.hp=UI.ProgressBar{width="100%",height=7,value=1,borderRadius=0,fillColor=C.red,backgroundColor={48,25,26,255}}
    self.xp=UI.ProgressBar{width="100%",height=3,value=0,borderRadius=0,fillColor=C.jade,backgroundColor={27,43,39,255}}
    self.health=T.Label("",small and 12 or 14,C.paper)
    self.level=T.Label("",10,C.muted)
    self.stage=T.Label("",small and 12 or 15,C.paper)
    self.record=T.Label("",small and 10 or 12,C.muted)
    self.comboLabel=T.Label("",small and 10 or 12,C.gold)
    self.weaponLabel=T.Label("",10,C.muted)
    self.hint=T.Label("",11,C.muted)
    self.skillButtons={} self.slots={}
    local controls={}
    for _,entry in ipairs({{"dash","空格 翻滚"},{"whirl","J 旋风"},{"blade","K 剑气"},{"burst","E 引燃"},{"potion","F 药水"}}) do
        local skill=entry[1]
        local b=T.Button(entry[2],function() game:Cast(skill) end,small and 62 or 82,"skill-"..skill)
        self.skillButtons[skill]=b controls[#controls+1]=b
    end
    controls[#controls+1]=T.Button("暂停",function() if game.state=="playing" then game.state="paused" end end,small and 43 or 55,"pause")
    self.muteButton=T.Button("静音",function() game.soundMuted=not game.soundMuted end,small and 43 or 55,"audio")
    controls[#controls+1]=self.muteButton
    local slots={}
    for i=1,6 do
        local name=T.Label("—",small and 10 or 11,C.muted,"center")
        local box=UI.Panel{id="weapon-slot-"..i,width=small and 31 or 43,height=24,padding=3,
            alignItems="center",justifyContent="center",backgroundColor=C.ink,borderColor=C.line,borderWidth=1,children={name}}
        self.slots[i]={name=name,box=box} slots[#slots+1]=box
    end
    self.leftHUD=T.Panel({self.health,self.hp,self.level,self.xp},{id="health-hud",width=small and 140 or 215,padding=8,gap=3,borderColor={93,59,48,255}})
    self.rightHUD=T.Panel({self.stage,self.record,self.comboLabel},{id="wave-hud",width=small and 200 or 268,padding=8,gap=3,borderColor={97,83,57,255}})
    self.top=UI.Panel{position="absolute",top=8,left=8,right=8,flexDirection="row",justifyContent="space-between",alignItems="flex-start",gap=6,
        pointerEvents="box-none",children={self.leftHUD,self.rightHUD}}
    self.bottom=UI.Panel{position="absolute",bottom=8,left=8,right=8,alignItems="center",gap=4,pointerEvents="box-none",children={
        T.Row({T.Row(slots,{gap=3}),self.weaponLabel},{gap=8}),T.Row(controls,{gap=4,justifyContent="center"})}}
    self.modal=UI.Panel{position="absolute",left=0,top=0,right=0,bottom=0,padding=8,backgroundColor={6,10,14,240},
        justifyContent="center",alignItems="center",pointerEvents="auto"}
    self.root=UI.Panel{width="100%",height="100%",pointerEvents="box-none",children={
        UI.SafeAreaView{width="100%",height="100%",pointerEvents="box-none",children={self.top,self.bottom,self.modal}}}}
    UI.SetRoot(self.root)
    self:Update()
end

function HUD:BuildModal()
    local g=self.game
    self.modal:ClearChildren()
    if g.state=="playing" then self.modal:Hide() return end
    self.modal:Show()
    local body,footer={},{}
    local title,subtitle,kicker="","",""
    if g.state=="title" then
        body,footer=Screens.Title(self)
        title="余烬契约" kicker="◆  THE LAST CONTRACT" subtitle="选择你的生存方式"
    elseif g.state=="shop" then
        body,footer=Screens.Shop(self)
        local r=g.lastWave
        title="余烬补给" kicker="SUPPLY / 第 "..g.wave.." 波完成"
        subtitle="击杀 "..r.kills.." · 材料 +"..r.materials.." · 利息 +"..r.interest.." · 收获 +"..r.harvest
    elseif g.state=="talent" then
        body,footer=Screens.Reward(self)
        title="战利强化"
        kicker="GROWTH / 选择属性强化"
        subtitle="战斗已暂停 · 选择后生效 · 按 1 / 2 / 3"
    elseif g.state=="paused" then
        body,footer=Screens.Pause(self)
        title="暂歇于阴影" kicker="PAUSED" subtitle="准备好了，就回到战场"
    else
        body,footer=Screens.Result(self)
        title=g.state=="win" and "契约完成" or "契约中断"
        kicker=g.state=="win" and "SURVIVED / 生存成功" or "FALLEN / 本局结束"
        subtitle=g.state=="win" and "你走出了阴影。下一局，换一种生存方式。" or "武装会重置，经验留在下一次选择里。"
    end
    ---@type Widget[]
    local children={T.Header(kicker,title,subtitle),T.Rule(C.gold)}
    children[#children+1]=UI.ScrollView{id="menu-scroll",width="100%",flexGrow=1,flexBasis=0,minHeight=0,
        scrollY=true,scrollX=false,showScrollbar=true,backgroundColor=C.ink,
        children={UI.Panel{width="100%",padding=12,gap=12,children=body}}}
    if g.state=="shop" and self.message~="" then children[#children+1]=T.Label(self.message,12,C.gold) end
    children[#children+1]=T.Rule()
    children[#children+1]=T.Row(footer,{id="menu-actions",width="100%",justifyContent="space-between",flexWrap="wrap",gap=8})
    local menuHeight=UI.GetHeight()>UI.GetWidth() and (UI.GetHeight()-32) or math.min(760,UI.GetHeight()-32)
    self.frame=T.Panel(children,{id="menu-frame",width=math.min(1120,UI.GetWidth()-32),height=menuHeight,
        padding=UI.GetWidth()<600 and 12 or 20,gap=10,borderColor=C.gold,backgroundColor=C.panel})
    self.modal:AddChild(self.frame)
end

function HUD:Notify(message)
    self.message=message or "" self.lastState=""
end

function HUD:Update()
    local g,p=self.game,self.game.player
    local compact=UI.GetWidth()<600
    if compact~=self.compact then self:Init(g) return end
    local key=table.concat({g.state,p.level,g.pendingLevels,g.gold,g.shopRevision,g.starter,g.role,g.forgeVouchers,g.recipeRevision or 0,
        UI.GetWidth(),UI.GetHeight(),g.soundMuted and 1 or 0},":")
    if self.lastChoice~=key or self.lastState~=g.state then
        if self.lastState~=g.state and g.state~="shop" then self.message="" end
        self.lastChoice=key self.lastState=g.state self:BuildModal()
    end
    self.top:SetVisible(g.state=="playing" or g.state=="paused") self.bottom:SetVisible(g.state=="playing")
    self.hp:SetValue(p.hp/p.maxHp) self.xp:SetValue(p.xp/p.xpNext)
    self.health:SetText("生命  "..math.ceil(p.hp).." / "..p.maxHp)
    self.health:SetFontColor(p.hp/p.maxHp<0.3 and C.red or C.paper)
    self.level:SetText("Lv."..p.level.."  ·  经验 "..math.floor(p.xp).." / "..p.xpNext)
    self.stage:SetText("第 "..g.wave.." / 8 波    "..math.ceil(g.waveTime).."s")
    self.stage:SetFontColor(g.waveTime<10 and C.red or C.paper)
    self.record:SetText("材料 "..g.gold.."   击杀 "..g.kills..(g.combo>=5 and ("   "..g.combo.."连杀") or ""))
    local burstReady=g.frenzyCharge>=8 and g.burstRecovery<=0 and g.overdriveTime<=0
    local energy=g.overdriveTime>0 and string.format("◆ 狂热 %.1fs",g.overdriveTime)
        or burstReady and "◆ E 引燃就绪" or ("引燃 "..g.frenzyCharge.." / 8")
    for _,e in ipairs(g.enemies) do if e.bounty and not e.dead then energy=energy.."  ·  夺宝 "..math.ceil(e.escapeTime).."s" break end end
    self.comboLabel:SetText(energy) self.comboLabel:SetFontColor((burstReady or g.overdriveTime>0) and C.gold or C.muted)
    self.muteButton:SetText(g.soundMuted and "开声音" or "静音")
    local recipes={}
    local slashProgress=g.weaponEvolutionProgress and g.weaponEvolutionProgress[1] or 0
    for kind,name in ipairs({"回斩"..math.floor(slashProgress).."/3","追魂","蔓延"}) do
        if g.weaponEvolutions[kind] and g:RecipeStatus(kind).tier>0 then recipes[#recipes+1]=name end
    end
    self.weaponLabel:SetText(#recipes>0 and table.concat(recipes," / ") or (#g.loadout.." / 6"))
    self.weaponLabel:SetFontColor(#recipes>0 and C.jade or C.muted)
    self.weaponLabel:SetStyle({maxWidth=compact and 112 or 240})
    for i,slot in ipairs(self.slots) do
        local w=g.loadout[i]
        slot.name:SetText(w and (({"剑","弓","杖"})[w.kind].." "..T.Tiers[w.tier]) or "—")
        slot.name:SetFontColor(w and T.Weapon[w.kind] or C.line)
        slot.box:SetBorderColor(w and T.Rarity[w.tier] or C.line)
    end
    self.skillButtons.dash:SetText(p.dashCd>0 and string.format("翻滚 %.1f",p.dashCd) or "空格 翻滚")
    self.skillButtons.whirl:SetText(p.whirlCd>0 and string.format("旋风 %.1f",p.whirlCd) or "J 旋风")
    self.skillButtons.blade:SetText(p.bladeCd>0 and string.format("剑气 %.1f",p.bladeCd) or "K 剑气")
    self.skillButtons.burst:SetText(g.overdriveTime>0 and string.format("狂热 %.1f",g.overdriveTime)
        or g.burstRecovery>0 and string.format("引燃 %.1f",g.burstRecovery)
        or burstReady and "E 引燃！" or ("引燃 "..g.frenzyCharge.."/8"))
    self.skillButtons.burst:SetBorderColor(burstReady and C.gold or C.line)
    self.skillButtons.potion:SetText("F 药水 ×"..p.potions)
    self.skillButtons.dash:SetDisabled(p.dashCd>0) self.skillButtons.whirl:SetDisabled(p.whirlCd>0)
    self.skillButtons.blade:SetDisabled(p.bladeCd>0) self.skillButtons.potion:SetDisabled(p.potions<=0 or p.hp>=p.maxHp)
    self.skillButtons.burst:SetDisabled(not burstReady)
end

return HUD
