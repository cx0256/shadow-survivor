-- Native Yoga layout evidence, collected without a desktop window. These are
-- layout/style traces, not screenshots of the GPU renderer.
require "main"
local UI=require "urhox-libs/UI"
local T=require "DungeonTheme"
local Survival=require "Survival"
local checks=0
local function check(ok,message) assert(ok,message) checks=checks+1 end
local function touchTarget(r,id)
    local dpr=math.max(1,graphics:GetDPR())
    if math.min(graphics:GetWidth(),graphics:GetHeight())/dpr>=600 then return end
    -- UI.Init has to run before GetWidth is meaningful. Compute here, rather
    -- than at module load where an infinite scale could falsely pass a test.
    local cssScale=graphics:GetWidth()/dpr/UI.GetWidth()
    check(cssScale>0 and cssScale<10,"initialized UI has a finite scale")
    print("[TouchTarget] "..cjson.encode({id=id,w=r.w*cssScale,h=r.h*cssScale}))
    check(r.w*cssScale>=43 and r.h*cssScale>=43,"mobile action has a 44px touch target (one framebuffer pixel rounding): "..id)
end

---@param widget Widget
local function collect(widget,out,clip)
    if not widget:IsVisible() then return end
    local p=widget.props
    local r=widget:GetAbsoluteLayoutForHitTest()
    if type(p.text)=="string" and p.text~="" then
        check(r.w>1 and r.h>1,"visible text must have nonzero layout: "..p.text)
    end
    local item={x=r.x,y=r.y,w=r.w,h=r.h,id=p.id or "",text=p.text or "",
        bg=p.backgroundColor,border=p.borderColor,borderWidth=p.borderWidth,
        color=p.fontColor or p.textColor,fontSize=p.fontSize or 14,align=p.textAlign or "left",
        disabled=p.disabled or false,button=type(p.onClick)=="function",radius=p.borderRadius,
        opacity=p.opacity or 1,clip=clip}
    out[#out+1]=item
    if p.id=="menu-scroll" then clip={x=r.x,y=r.y,w=r.w,h=r.h} end
    for _,child in ipairs(widget:GetChildren()) do collect(child,out,clip) end
end

DungeonApp.onReady=function()
    DungeonApp.testing=true
    local g=DungeonApp.game local hud=DungeonApp.ui
    local function sendTouch(event,id,x,y)
        local data=VariantMap() data["TouchID"]=id data["X"]=x data["Y"]=y
        SendEvent(event,data)
    end
    local function tap(id)
        local target=hud.root:FindById(id)
        check(target~=nil,"touch target exists: "..id)
        local r=target:GetAbsoluteLayoutForHitTest()
        local x=math.floor((r.x+r.w/2)*graphics:GetWidth()/UI.GetWidth())
        local y=math.floor((r.y+r.h/2)*graphics:GetHeight()/UI.GetHeight())
        sendTouch("TouchBegin",1,x,y)
        sendTouch("TouchEnd",1,x,y)
    end
    local function snapshot(name,primary)
        hud:Update() UI.Layout()
        if primary then
            local b=hud.root:FindById(primary)
            check(b~=nil,"primary action exists: "..name)
            local r=b:GetAbsoluteLayoutForHitTest()
            check(r.w>20 and r.h>=35 and r.x>=-1 and r.x+r.w<=UI.GetWidth()+1,
                "primary action fits width: "..name)
            check(r.y>=-1 and r.y+r.h<=UI.GetHeight()+1,"primary action stays visible: "..name)
            touchTarget(r,primary)
        end
        local rows={} collect(hud.root,rows,false)
        for offset=1,#rows,8 do
            local batch={}
            for i=offset,math.min(#rows,offset+7) do batch[#batch+1]=rows[i] end
            print("[UILayoutBatch] "..cjson.encode({name=name,w=UI.GetWidth(),h=UI.GetHeight(),offset=offset,widgets=batch}))
        end
    end
    local function alignedActions(cardPrefix,actionPrefix,count,inset)
        local cards,actions={},{}
        for i=1,count do
            local card=hud.root:FindById(cardPrefix..i)
            local action=hud.root:FindById(actionPrefix..i)
            check(card~=nil and action~=nil,"choice card and action exist")
            local c=card:GetAbsoluteLayoutForHitTest()
            local a=action:GetAbsoluteLayoutForHitTest()
            -- Yoga rounds each edge to framebuffer pixels. At narrow sizes a
            -- single pixel can exceed one UI unit; allow exactly that rounding.
            local pixel=UI.GetWidth()/graphics:GetWidth()
            check(math.abs(a.h-T.ButtonHeight())<=pixel+0.01,"choice actions retain a consistent touch height")
            check(a.x>=c.x and a.x+a.w<=c.x+c.w+1,"choice action fits its card width")
            check(math.abs(c.y+c.h-a.y-a.h-inset)<=2*pixel+0.01,"choice action anchors to card bottom")
            for _,child in ipairs(card:GetChildren()) do
                if child.props.position~="absolute" then
                    local r=child:GetAbsoluteLayoutForHitTest()
                    check(r.y+r.h<=a.y-3,"choice content does not overlap its action")
                end
            end
            cards[i]=c actions[i]=a
            for j=1,i-1 do
                if math.abs(cards[j].y-c.y)<2 then
                    check(math.abs(actions[j].y-a.y)<2,"actions in the same row align")
                    check(math.abs(cards[j].h-c.h)<2,"cards in the same row have equal height")
                end
            end
        end
        if UI.GetWidth()>=760 then
            check(math.abs(cards[1].y-cards[2].y)<2 and cards[2].x>cards[1].x,
                "wide choices share a horizontal row")
        elseif UI.GetWidth()<620 then
            check(cards[2].y>=cards[1].y+cards[1].h,"compact choices stack without overlap")
        end
    end
    snapshot("title","start")
    local intro=hud.root:FindById("title-intro")
    local introRect=intro:GetAbsoluteLayoutForHitTest()
    for _,child in ipairs(intro:GetChildren()) do
        local r=child:GetAbsoluteLayoutForHitTest()
        check(r.y>=introRect.y-1 and r.y+r.h<=introRect.y+introRect.h+1,"title introduction content stays inside its panel")
    end
    alignedActions("starter-card-","starter-",3,10)
    if T.TouchLayout() then
        local original=g.starter
        g:SetWeapon(1) hud:Update()
        local choice=hud.root:FindById("starter-2")
        choice.props.onClick(choice)
        hud:Update() UI.Layout()
        local start=hud.root:FindById("start")
        check(g.starter==2 and start.props.text:find("游侠长弓",1,true)~=nil,
            "phone start action names the currently selected weapon without scrolling")
        local bounds=start:GetAbsoluteLayoutForHitTest()
        check(bounds.y+bounds.h<=UI.GetHeight()+1,"updated start action remains in the first screen")
        g:SetWeapon(original) hud:Update()
    end
    g.save.bestWave=0 g.save.clears=0
    UI.Layout()
    tap("start")
    check(g.state=="playing" and g.wave==1,"touching Start enters the first wave")
    g:Finish(false)
    snapshot("first-wave-defeat","restart")
    local retryTip=hud.root:FindById("first-wave-retry-tip")
    check(retryTip~=nil,"first-wave defeat shows a concrete retry tip")
    local tipBounds=retryTip:GetAbsoluteLayoutForHitTest()
    local resultViewport=hud.root:FindById("menu-scroll"):GetAbsoluteLayoutForHitTest()
    check(tipBounds.y>=resultViewport.y-1 and tipBounds.y+tipBounds.h<=resultViewport.y+resultViewport.h+1,
        "retry tip stays visible without scrolling")
    tap("restart")
    hud:Update()
    check(g.state=="playing" and g.wave==1 and g.save.bestWave==1
        and hud.objective.props.text:find("武器会自动攻击",1,true)~=nil,
        "first-wave retry repeats the control hint after recording the defeat")
    check(g.saveDirty,"the normal restart button preserves the previous run's pending save")
    g.save.bestWave=2
    hud:Update()
    check(hud.objective.props.text:find("武器会自动攻击",1,true)==nil,
        "experienced players see the wave objective immediately")
    g.save.bestWave=1
    g.waveTime=0.001
    g:Update(0.02,0,0)
    snapshot("first-shop","next-wave")
    local upgrade=hud.root:FindById("buy-1")
    local target=upgrade:GetAbsoluteLayoutForHitTest()
    local viewport=hud.root:FindById("menu-scroll"):GetAbsoluteLayoutForHitTest()
    check(target.y>=viewport.y-1 and target.y+target.h<=viewport.y+viewport.h+1,
        "starter upgrade is visible without scrolling")
    local progress=hud.root:FindById("recipe-progress")
    check(progress and progress:GetChildren()[1].props.text:find("II 阶",1,true),"first shop shows the missing starter weapon tier")
    local warning=hud.root:FindById("shop-reroll-row"):GetChildren()[1]
    check(warning.props.text:find("刷新会替换首波补给",1,true)~=nil,
        "refresh shows the consequence while the starter offer is unlocked")
    local warningBounds=warning:GetAbsoluteLayoutForHitTest()
    local rerollBounds=hud.root:FindById("reroll"):GetAbsoluteLayoutForHitTest()
    check(warningBounds.y<=rerollBounds.y+1,"scrolling to refresh reveals its warning first")
    local wallet=g.gold
    tap("buy-1")
    check(g.gold==wallet-8 and g:RecipeStatus(g.starter).tier==2,
        "first shop action buys the matching tier II upgrade")
    check(hud.message=="合成成功："..T.WeaponName(g.starter,2),
        "the shop confirms the resulting tier instead of the purchased tier")
    snapshot("first-shop-after-fusion","next-wave")
    progress=hud.root:FindById("recipe-progress")
    check(progress and not progress:GetChildren()[1].props.text:find("II 阶",1,true),
        "the recipe hint drops the weapon requirement as soon as the upgrade is bought")
    local remainingWarning=hud.root:FindById("shop-reroll-row"):GetChildren()[1].props.text
    check((remainingWarning:find("刷新会替换首波补给",1,true)~=nil)==(g.starter==2),
        "the replacement warning stays only if the discounted bow sidearm remains")
    hud.root:FindById("menu-scroll"):SetScroll(0,60)
    tap("next-wave")
    hud:Update()
    check(g.state=="playing" and g.wave==2 and g.waveActive,
        "the normal next-wave button resumes combat after the starter purchase")
    check(g:RecipeStatus(g.starter).tier==2 and hud.message=="",
        "the upgrade persists into wave two and the shop feedback clears")
    g.state="title" g:SetWeapon(2)
    hud:Update() UI.Layout()
    tap("start")
    g.waveTime=0.001 g:Update(0.02,0,0)
    hud:Update() UI.Layout()
    local sidearm=hud.root:FindById("buy-2"):GetAbsoluteLayoutForHitTest()
    local firstShopScroll=hud.root:FindById("menu-scroll")
    local firstShopViewport=firstShopScroll:GetAbsoluteLayoutForHitTest()
    firstShopScroll:UpdateContentSize()
    firstShopScroll:SetScroll(0,math.max(0,sidearm.y-firstShopViewport.y-firstShopViewport.h/2))
    tap("buy-2")
    check(#g.loadout==2 and g.loadout[1].kind==2 and g.loadout[2].kind==1 and g.gold==0,
        "touching the scrolled sidearm card buys the bow and sword route")
    hud:Update() UI.Layout()
    tap("next-wave")
    check(g.state=="playing" and g.wave==2 and #g.loadout==2,"touching Next Wave carries both weapons into combat")
    print("[P01TouchChecks] start, restart, both first purchases, and next wave via native touch passed")
    g:Start()
    g.loadout={{kind=1,tier=4,cd=0,angle=0},{kind=2,tier=2,cd=0,angle=0},{kind=3,tier=3,cd=0,angle=0},
        {kind=1,tier=2,cd=0,angle=0},{kind=2,tier=1,cd=0,angle=0},{kind=3,tier=1,cd=0,angle=0}}
    g.player.hp=21 g.player.level=12 g.gold=12345 g.kills=1481 g.overdriveTime=3.5
    g.combo=24
    snapshot("combat")
    hud:Update()
    check(not UI.IsLayoutDirty(),"an unchanged combat frame does not invalidate native layout")
    local modalKey=hud.lastChoice
    g.gold=g.gold+1
    hud:Update()
    check(hud.lastChoice==modalKey and hud.record.props.text:find(tostring(g.gold),1,true)~=nil,
        "collecting materials updates the counter without rebuilding the hidden modal")
    UI.Layout()
    local screenW,screenH=graphics:GetWidth(),graphics:GetHeight()
    local moveX,moveY=math.floor(screenW*0.18),math.floor(screenH*0.64)
    check(hud:CanStartMovement(moveX,moveY),"test finger starts in the movement zone")
    local dash=hud.root:FindById("skill-dash"):GetAbsoluteLayoutForHitTest()
    local dashX=math.floor((dash.x+dash.w/2)*screenW/UI.GetWidth())
    local dashY=math.floor((dash.y+dash.h/2)*screenH/UI.GetHeight())
    sendTouch("TouchBegin",1,moveX,moveY)
    sendTouch("TouchBegin",2,dashX,dashY)
    sendTouch("TouchEnd",2,dashX,dashY)
    sendTouch("TouchEnd",1,moveX,moveY)
    check(g.player.dashCd>0,"a second finger can trigger the real dash button with a movement contact held")
    local a=hud.leftHUD:GetAbsoluteLayoutForHitTest() local b=hud.rightHUD:GetAbsoluteLayoutForHitTest()
    check(a.x+a.w<=b.x+1,"combat HUD clusters never overlap")
    for i=1,6 do check(hud.root:FindById("weapon-slot-"..i)~=nil,"all six weapon slots exist") end
    for _,id in ipairs({"skill-dash","skill-whirl","skill-blade","skill-burst","skill-potion","pause","audio"}) do
        local action=hud.root:FindById(id)
        local r=action:GetAbsoluteLayoutForHitTest()
        check(r.w>=35 and r.x>=0 and r.x+r.w<=UI.GetWidth()+1,"combat control stays within viewport: "..id)
        check(r.y>=0 and r.y+r.h<=UI.GetHeight()+1,"combat control stays within viewport height: "..id)
        touchTarget(r,id)
        for _,otherId in ipairs({"skill-dash","skill-whirl","skill-blade","skill-burst","skill-potion","pause","audio"}) do
            if id<otherId then
                local other=hud.root:FindById(otherId):GetAbsoluteLayoutForHitTest()
                check(r.x+r.w<=other.x+1 or other.x+other.w<=r.x+1 or r.y+r.h<=other.y+1 or other.y+other.h<=r.y+1,
                    "combat actions do not overlap: "..id.." / "..otherId)
            end
        end
    end
    g.overdriveTime=0 g.frenzyCharge=8 g.burstRecovery=0
    snapshot("burst-ready","skill-burst")
    check(not hud.root:FindById("skill-burst").props.disabled,"ready state visibly enables burst")
    g.wave=3 g.state="shop" g.waveActive=false g.overdriveTime=0
    g.shop={{type="weapon",kind=1,tier=2,cost=25,sold=false,locked=true},
        {type="weapon",kind=2,tier=1,cost=19,sold=true,locked=false},
        {type="item",item={name="玻璃之心",desc="伤害 +25% / 生命上限 -15",mods={damage=0.25,hp=-15}},cost=29,sold=false,locked=false},
        {type="item",item={name="远古风暴之心",desc="用生命换取高额攻速：这是较长说明的换行检查"},cost=12399,sold=false,locked=false}}
    g.shopRevision=g.shopRevision+1
    snapshot("shop","next-wave")
    local scroll=hud.root:FindById("menu-scroll")
    local _,initialOffset=scroll:GetScroll()
    check(initialOffset==0,"a new wave shop opens at the top")
    scroll:UpdateContentSize()
    scroll:SetScroll(0,90)
    local _,beforeLock=scroll:GetScroll()
    check(beforeLock>0,"test shop content extends past the first screen")
    local lock=hud.root:FindById("lock-3")
    lock.props.onClick(lock)
    hud:Update() UI.Layout()
    local _,afterLock=hud.root:FindById("menu-scroll"):GetScroll()
    check(math.abs(afterLock-beforeLock)<1,"locking a product keeps the same shop scroll position")
    local buyItem=hud.root:FindById("buy-3")
    buyItem.props.onClick(buyItem)
    hud:Update() UI.Layout()
    local _,afterPurchase=hud.root:FindById("menu-scroll"):GetScroll()
    check(g.shop[3].sold and math.abs(afterPurchase-beforeLock)<1,
        "buying a product and showing purchase feedback keeps the shop position")
    hud.root:FindById("menu-scroll"):ScrollToTop()
    alignedActions("recipe-card-","recipe-evolve-",3,10)
    alignedActions("shop-card-","buy-",4,12)
    check(hud.root:FindById("buy-2").props.disabled,"sold card is visibly disabled")
    check(hud.root:FindById("lock-2").props.disabled,"sold card cannot be locked")
    g.forgeVouchers=2
    snapshot("treasure-shop","next-wave")
    for kind=1,3 do check(hud.root:FindById("forge-claim-"..kind)~=nil,"treasure weapon choice exists") end
    g.items={"狂战护符","猎人镜片","火种"} g.shopRevision=g.shopRevision+1
    snapshot("recipes-ready","next-wave")
    for kind=1,3 do check(not hud.root:FindById("recipe-evolve-"..kind).props.disabled,"eligible recipe action is enabled") end
    local evolve=hud.root:FindById("recipe-evolve-2") evolve.props.onClick(evolve)
    snapshot("recipe-active","next-wave")
    check(g.weaponEvolutions[2] and hud.root:FindById("recipe-evolve-2").props.disabled,"recipe activation refreshes visible state")
    check(hud.root:FindById("recipe-evolve-1").props.disabled and hud.root:FindById("recipe-evolve-3").props.disabled,
        "other recipe choices visibly lock after the run core is selected")
    check(hud.root:FindById("talent-1")==nil,"removed attribute reward action never appears")
    check(hud.root:FindById("evolution-1")==nil,"removed contract action never appears")
    scroll=hud.root:FindById("menu-scroll")
    scroll:UpdateContentSize()
    scroll:SetScroll(0,90)
    local reroll=hud.root:FindById("reroll")
    reroll.props.onClick(reroll)
    hud:Update() UI.Layout()
    local _,afterReroll=hud.root:FindById("menu-scroll"):GetScroll()
    check(g.rolls==1 and math.abs(afterReroll-90)<1,"refreshing products keeps the shop position")
    g.state="paused" snapshot("pause","resume")
    g.items={"火种","火种","玻璃之心","磨刀石","血色契约"}
    g.state="win" snapshot("victory","restart")
    g:Finish(false) snapshot("defeat","restart")
    local goal=hud.root:FindById("retry-goal")
    check(goal and goal:GetChildren()[1].props.text:find("新纪录",1,true)~=nil
        and goal:GetChildren()[2].props.text:find("第 4 波",1,true)~=nil,
        "a new best wave shows the next wave as a replay goal")
    local goalBounds=goal:GetAbsoluteLayoutForHitTest()
    local goalViewport=hud.root:FindById("menu-scroll"):GetAbsoluteLayoutForHitTest()
    check(goalBounds.y>=goalViewport.y-1 and goalBounds.y+goalBounds.h<=goalViewport.y+goalViewport.h+1,
        "the replay goal is visible without scrolling")
    g:Start() g.wave=8 g.save.bestWave=8
    g:Finish(false) snapshot("final-wave-defeat","restart")
    goal=hud.root:FindById("retry-goal")
    check(goal and goal:GetChildren()[1].props.text:find("最高纪录",1,true)~=nil
        and goal:GetChildren()[2].props.text:find("击败首领",1,true)~=nil,
        "a tied final wave shows the first-clear target without a false record")
    for kind,combatLabel in ipairs({"回斩","追魂","蔓延"}) do
        g.state="title" g:SetWeapon(kind) g:Start()
        g.wave=2 g.waveActive=false g.state="shop"
        g.loadout[1].tier=2
        g.forgeVouchers=2 g.gold=8
        local recipe=g:RecipeStatus(kind)
        g.shop[1]={type="item",item={name=recipe.item,desc="",mods={}},cost=8,sold=false,locked=false}
        hud:Update() UI.Layout()
        local hint=hud.root:FindById("recipe-progress")
        check(hint and hint:GetChildren()[1].props.text:find(recipe.item,1,true) and not hud.root:FindById("recipe-quick-evolve"),
            "each starter shows its remaining relic before the shortcut appears")
        hud:BuyShop(1)
        hud:Update() UI.Layout()
        local action=hud.root:FindById("recipe-quick-evolve")
        check(action~=nil,"buying the last ingredient exposes the shortcut for each starter")
        local bounds=action:GetAbsoluteLayoutForHitTest()
        local shopViewport=hud.root:FindById("menu-scroll"):GetAbsoluteLayoutForHitTest()
        check(bounds.y>=shopViewport.y-1 and bounds.y+bounds.h<=shopViewport.y+shopViewport.h+1,
            "the shortcut is visible at the top of the shop")
        touchTarget(bounds,"recipe-quick-evolve")
        tap("recipe-quick-evolve")
        hud:Update() UI.Layout()
        local active=hud.root:FindById("recipe-active")
        check(g.weaponEvolutions[kind] and g.forgeVouchers==1 and #g.recipeUnlocks==1
            and active and active:GetChildren()[1].props.text:find(recipe.name,1,true)
            and not hud.root:FindById("recipe-quick-evolve"),
            "touching the shortcut spends one voucher and displays the active core instead")
        tap("next-wave")
        hud:Update()
        check(g.state=="playing" and g.wave==3 and hud.weaponLabel.props.text:find(combatLabel,1,true),
            "the combat HUD carries the active core into the next wave")
    end
    print("[P02RecipeDiscovery] three recipe shortcuts activated by touch")
    g:Start()
    local exitButton=hud.root:FindById("trial-exit")
    hud:Update() UI.Layout()
    check(not exitButton:IsVisible(),"there is no exit control before completing an objective")
    Survival.Pickup(g,{kind="material",value=10,x=g.player.x,y=g.player.y,treasure=true})
    check(g.trial.exit~=nil,
        "collecting the objective creates an exit at the player")
    hud:Update() UI.Layout()
    local exitBounds=exitButton:GetAbsoluteLayoutForHitTest()
    local bottom=hud.bottom:GetAbsoluteLayoutForHitTest()
    check(exitButton:IsVisible() and exitBounds.x>=0 and exitBounds.x+exitBounds.w<=UI.GetWidth()+1
        and exitBounds.y>=0 and exitBounds.y+exitBounds.h<=bottom.y,
        "the contextual exit control fits above combat skills")
    touchTarget(exitBounds,"trial-exit")
    for _=1,20 do g:Update(0.034,0,0) end
    check(g.state=="playing","standing in the ring without touching the button keeps combat active")
    tap("trial-exit")
    hud:Update()
    check(g.trial.exit.departing and not exitButton:IsVisible(),"touching Exit starts the countdown once")
    for _=1,20 do g:Update(0.034,0,0) end
    check(g.state=="shop" and g.trial.exit.used and g.trialTimeSaved>0,"holding position completes the real exit path")
    print("[ExplicitExitChecks] touch requires deliberate exit")
    g.state="title" hud:Update()
    print("[UIStyleTests] "..checks.." native layout and state checks passed")
end
