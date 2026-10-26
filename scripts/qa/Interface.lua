require "main"
local UI=require "urhox-libs/UI"
---@type SurvivorRulesAPI
local Survival=require "Survival"
DungeonApp.onReady=function()
    DungeonApp.testing=true
    local g=DungeonApp.game local hud=DungeonApp.ui
    local checks=0
    local function check(ok,message) assert(ok,message) checks=checks+1 end
    local function key(code)
        local data=VariantMap() data["Key"]=code SendEvent("KeyDown",data) hud:Update()
    end
    key(KEY_2) check(g.starter==2,"starter selection uses title keyboard")
    key(KEY_M) check(g.soundMuted,"M mutes before starting")
    key(KEY_RETURN) check(g.state=="playing" and g.loadout[1].kind==2,"Enter starts with selected owned weapon")
    check(g.soundMuted,"mute preference survives starting run")
    key(KEY_M) check(not g.soundMuted,"M restores audio during combat")
    g:GainXp(12) hud:Update()
    check(g.state=="playing" and g.pendingLevels==1,"level stores one attribute choice until wave end")
    check(hud.root:FindById("evolution-1")==nil,"no contract choice interrupts combat")
    local clock=g.waveTime g:Update(0.02,1,0)
    check(g.waveTime<clock,"level growth leaves combat running")
    key(KEY_ESCAPE) check(g.state=="paused","Escape pauses")
    key(KEY_ESCAPE) check(g.state=="playing","Escape resumes")
    key(KEY_J) check(g.player.whirlCd>0,"whirl action")
    key(KEY_K) check(g.player.bladeCd>0,"blade action")
    g.frenzyCharge=8 g.burstRecovery=0 hud:Update()
    check(not hud.root:FindById("skill-burst").props.disabled,"charged burst is available in HUD")
    key(KEY_E)
    check(g.burstCount==1 and g.overdriveTime==2 and g.frenzyCharge==0,"E ignites the charged burst")
    check(hud.root:FindById("skill-burst").props.disabled,"active burst cannot be triggered twice")
    g.player.hp=30 key(KEY_F) check(g.player.potions==1 and g.player.hp>30,"potion action")
    g.overdriveTime=4
    g.waveTime=0.001 g:Update(0.02,0,0) hud:Update()
    while g.state=="talent" do g:ChooseTalent(1) end
    hud:Update()
    check(g.state=="shop" and hud.root:FindById("next-wave"),"timed wave opens shop UI")
    check(g.overdriveTime==0,"shop damage previews exclude expired combat burst")
    g.forgeVouchers=1 hud:Update()
    local forge=hud.root:FindById("forge-claim-3")
    check(forge~=nil,"shop shows a choice of treasure weapons")
    local wallet=g.gold
    forge.props.onClick(forge) hud:Update()
    check(g.forgeVouchers==0 and g.loadout[#g.loadout].kind==3 and g.gold==wallet,
        "free forge callback grants the selected kind without spending materials")
    g.gold=100 g.shop[1]={type="weapon",kind=1,tier=1,cost=10,locked=false,sold=false}
    g.shopRevision=g.shopRevision+1 hud:Update()
    local buy=hud.root:FindById("buy-1") buy.props.onClick(buy)
    check(#g.loadout==3 and g.gold==90,"pointer buy callback owns another weapon")
    hud:Update() local lock=hud.root:FindById("lock-2") lock.props.onClick(lock)
    check(g.shop[2].locked,"pointer lock callback")
    local kept=g.shop[2] key(KEY_R)
    check(g.shop[2]==kept,"keyboard refresh respects locks")
    g.gold=0 g.shop[4]={type="weapon",kind=3,tier=1,cost=999,sold=false,locked=false}
    key(KEY_4)
    check(g.gold==0 and hud.message=="材料不足","keyboard purchases show the same failure feedback as pointer input")
    g.gold=10000
    for _,item in ipairs(Survival.Items) do
        g.shop[1]={type="item",item=item,cost=10,sold=false,locked=false}
        g.shopRevision=g.shopRevision+1 hud:Update()
        local itemBuy=hud.root:FindById("buy-1") itemBuy.props.onClick(itemBuy)
        hud:Update()
    end
    check(#g.items==#Survival.Items,"all tradeoff item callbacks and fractional stat summaries render without errors")
    g.loadout[1].tier=2 g.forgeVouchers=1 g.shopRevision=g.shopRevision+1 hud:Update()
    local evolve=hud.root:FindById("recipe-evolve-2")
    check(evolve and not evolve.props.disabled,"complete recipe offers an enabled native action")
    local money=g.gold
    evolve.props.onClick(evolve) hud:Update()
    check(g.weaponEvolutions[2] and g.forgeVouchers==0 and g.gold==money,"native action spends one voucher to evolve chosen kind")
    evolve=hud.root:FindById("recipe-evolve-2")
    check(evolve.props.disabled,"unlocked native recipe cannot be purchased again")
    evolve.props.onClick(evolve)
    check(#g.recipeUnlocks==1 and g.forgeVouchers==0,"stale double click cannot duplicate evolution")
    key(KEY_RETURN) check(g.wave==2 and g.state=="playing","Enter starts next wave")
    g:Finish(false) hud:Update()
    local restart=hud.root:FindById("restart") restart.props.onClick(restart)
    check(g.state=="playing" and g.wave==1 and #g.loadout==1,"pointer restart clears loadout upgrades")
    check(not g.weaponEvolutions[2] and #g.recipeUnlocks==0,"restart clears recipe UI state")
    g.state="title" hud:Update() UI.Layout()
    print("[SurvivorTests] "..checks.." interface checks passed")
    local total=require "qa/Simulation"
    print("[SurvivorTests] "..total.." simulation checks passed")
end
