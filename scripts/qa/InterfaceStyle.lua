-- Native Yoga layout evidence, collected without a desktop window. These are
-- layout/style traces, not screenshots of the GPU renderer.
require "main"
local UI=require "urhox-libs/UI"
local checks=0
local function check(ok,message) assert(ok,message) checks=checks+1 end

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
    local function snapshot(name,primary)
        hud:Update() UI.Layout()
        if primary then
            local b=hud.root:FindById(primary)
            check(b~=nil,"primary action exists: "..name)
            local r=b:GetAbsoluteLayoutForHitTest()
            check(r.w>20 and r.h>=35 and r.x>=-1 and r.x+r.w<=UI.GetWidth()+1,
                "primary action fits width: "..name)
            check(r.y>=-1 and r.y+r.h<=UI.GetHeight()+1,"primary action stays visible: "..name)
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
            check(a.h>=41 and a.h<=43,"choice actions retain a consistent touch height")
            check(a.x>=c.x and a.x+a.w<=c.x+c.w+1,"choice action fits its card width")
            check(math.abs(c.y+c.h-a.y-a.h-inset)<=2,"choice action anchors to card bottom")
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
    alignedActions("starter-card-","starter-",3,10)
    g:Start()
    g.loadout={{kind=1,tier=4,cd=0,angle=0},{kind=2,tier=2,cd=0,angle=0},{kind=3,tier=3,cd=0,angle=0},
        {kind=1,tier=2,cd=0,angle=0},{kind=2,tier=1,cd=0,angle=0},{kind=3,tier=1,cd=0,angle=0}}
    g.player.hp=21 g.player.level=12 g.gold=12345 g.kills=1481 g.overdriveTime=3.5
    g.combo=24
    snapshot("combat")
    local a=hud.leftHUD:GetAbsoluteLayoutForHitTest() local b=hud.rightHUD:GetAbsoluteLayoutForHitTest()
    check(a.x+a.w<=b.x+1,"combat HUD clusters never overlap")
    for i=1,6 do check(hud.root:FindById("weapon-slot-"..i)~=nil,"all six weapon slots exist") end
    for _,id in ipairs({"skill-dash","skill-whirl","skill-blade","skill-burst","skill-potion","pause","audio"}) do
        local action=hud.root:FindById(id)
        local r=action:GetAbsoluteLayoutForHitTest()
        check(r.w>=35 and r.x>=0 and r.x+r.w<=UI.GetWidth()+1,"combat control stays within viewport: "..id)
    end
    g.overdriveTime=0 g.frenzyCharge=8 g.burstRecovery=0
    snapshot("burst-ready","skill-burst")
    check(not hud.root:FindById("skill-burst").props.disabled,"ready state visibly enables burst")
    g.wave=3 g.state="shop" g.waveActive=false g.overdriveTime=0
    g.shop={{type="weapon",kind=1,tier=2,cost=25,sold=false,locked=true},
        {type="weapon",kind=2,tier=1,cost=19,sold=true,locked=false},
        {type="item",item={name="玻璃之心",desc="伤害 +25% / 生命上限 -15"},cost=29,sold=false,locked=false},
        {type="item",item={name="远古风暴之心",desc="用生命换取高额攻速：这是较长说明的换行检查"},cost=12399,sold=false,locked=false}}
    g.shopRevision=g.shopRevision+1
    snapshot("shop","next-wave")
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
    g.state="talent" g.pendingLevels=2
    g.choices={{name="锋锐",desc="攻击力 +5"},{name="汲取",desc="造成伤害的5%回复生命"},{name="坚韧",desc="生命上限 +28，并回复28点"}}
    snapshot("talent","talent-1")
    alignedActions("talent-card-","talent-",3,18)
    check(hud.root:FindById("evolution-1")==nil,"removed contract action never appears")
    g.state="paused" snapshot("pause","resume")
    g.items={"火种","火种","玻璃之心","磨刀石","血色契约"}
    g.state="win" snapshot("victory","restart")
    g.state="dead" snapshot("defeat","restart")
    g.state="title" hud:Update()
    print("[UIStyleTests] "..checks.." native layout and state checks passed")
end
