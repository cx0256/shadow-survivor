-- Dark dungeon port. Lifecycle and UI initialization based on scaffold-2d.lua.
local UI=require "urhox-libs/UI"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@class DungeonViewAPI
---@field ToArena fun(x: number, y: number): number, number
---@field Draw fun(vg: NVGContextWrapper, g: table)
---@type DungeonViewAPI
local View=require "DungeonView"
---@class DungeonUIAPI
---@field New fun(game: table): table
---@type DungeonUIAPI
local HUD=require "DungeonUI"
local SFX=require "CombatAudio"
local audioRunTime=0

-- App is also the controlled-entry seam for local runtime acceptance tests.
DungeonApp={game=Dungeon.New({}),testing=false,ui={},onReady=function() end,onFrame=function(_dt) end}
---@type NVGContextWrapper|nil
local vg=nil
---@type table
local hud={}
local stick={id=-1,x=0,y=0,mx=0,my=0}

local function LoadSave()
    local data={}
    if fileSystem:FileExists("shadow-dungeon-v2.json") then
        local file=File("shadow-dungeon-v2.json",FILE_READ)
        if file:IsOpen() then
            local ok,result=pcall(cjson.decode,file:ReadString())
            file:Close()
            if ok and type(result)=="table" then data=result end
        end
    end
    return data
end

local function SaveProgress()
    local game=DungeonApp.game
    if not game.saveDirty or DungeonApp.testing then return end
    local file=File("shadow-dungeon-v2.json",FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode(game.save)) file:Close()
        game.saveDirty=false
    end
end

function Start()
    graphics.windowTitle="暗影幸存者 · TapTap 制造"
    input.mouseVisible=true
    input.mouseMode=MM_FREE
    DungeonApp.game=Dungeon.New(LoadSave())
    SFX.Init()
    -- Keep UI native to Maker; raw NanoVG is reserved for arena/game effects.
    UI.Init({theme="default-dark",scale=UI.Scale.DEFAULT,
        fonts={{family="sans",weights={normal="Fonts/MiSans-Regular.ttf"}}}})
    vg=nvgCreate(1)
    nvgCreateFont(vg,"dungeon","Fonts/MiSans-Regular.ttf")
    hud=HUD.New(DungeonApp.game)
    DungeonApp.ui=hud
    SubscribeToEvent(vg,"NanoVGRender","HandleDungeonRender")
    SubscribeToEvent("Update","HandleDungeonUpdate")
    SubscribeToEvent("KeyDown","HandleDungeonKeyDown")
    SubscribeToEvent("InputFocus","HandleDungeonFocus")
    print("[Dungeon] Ready: sword / bow / staff; local single player")
    DungeonApp.onReady()
end

function Stop()
    SaveProgress()
    UI.Shutdown()
    SFX.Stop()
    if vg then nvgDelete(vg) vg=nil end
end

---@param eventType string
---@param eventData InputFocusEventData
function HandleDungeonFocus(eventType,eventData)
    if eventData["Focus"]:GetBool() then return end
    stick.id=-1 stick.mx=0 stick.my=0
    if not DungeonApp.testing and DungeonApp.game.state=="playing" then DungeonApp.game.state="paused" end
end

local function TouchMovement()
    local found=false
    for i=0,input.numTouches-1 do
        local t=input:GetTouch(i)
        local x,y=View.ToArena(t.position.x,t.position.y)
        if stick.id==t.touchID then
            local dx,dy=x-stick.x,y-stick.y
            local length=math.sqrt(dx*dx+dy*dy)
            stick.mx=dx/math.max(45,length) stick.my=dy/math.max(45,length)
            found=true
        elseif stick.id==-1 and x<350 and y>330 and y<550 and DungeonApp.game.state=="playing" then
            stick.id=t.touchID stick.x=x stick.y=y stick.mx=0 stick.my=0 found=true
        end
    end
    if not found then stick.id=-1 stick.mx=0 stick.my=0 end
    local g=DungeonApp.game
    g.touchActive=found g.stickX=stick.x g.stickY=stick.y g.stickMX=stick.mx g.stickMY=stick.my
end

---@param eventType string
---@param eventData UpdateEventData
function HandleDungeonUpdate(eventType,eventData)
    local dt=eventData["TimeStep"]:GetFloat()
    local game=DungeonApp.game
    TouchMovement()
    local mx,my=stick.mx,stick.my
    if game.state=="playing" then
        if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then mx=mx-1 end
        if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then mx=mx+1 end
        if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then my=my-1 end
        if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then my=my+1 end
    else stick.id=-1 end
    game:Update(dt,mx,my)
    if game.runTime<audioRunTime then SFX.Reset() end
    audioRunTime=game.runTime
    SFX.Update(game)
    hud:Update()
    SaveProgress()
    DungeonApp.onFrame(dt)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleDungeonKeyDown(eventType,eventData)
    if eventData:GetBool("Repeat") then return end
    local key=eventData["Key"]:GetInt()
    local game=DungeonApp.game
    if key==KEY_M then game.soundMuted=not game.soundMuted return end
    if game.state=="title" then
        if key==KEY_Q then game.role=game.role%4+1 end
        if key==KEY_1 then game:SetWeapon(1) elseif key==KEY_2 then game:SetWeapon(2) elseif key==KEY_3 then game:SetWeapon(3) end
        if key==KEY_RETURN or key==KEY_SPACE then game:Start() end
        if key==KEY_ESCAPE then game.state="title" end
    elseif game.state=="dead" or game.state=="win" then
        if key==KEY_R or key==KEY_RETURN then game:Start() end
    elseif game.state=="talent" then
        if key==KEY_1 then game:ChooseTalent(1) elseif key==KEY_2 then game:ChooseTalent(2) elseif key==KEY_3 then game:ChooseTalent(3) end
    elseif game.state=="shop" then
        if key==KEY_RETURN then game:BeginWave()
        elseif key==KEY_R then
            if not game:RerollShop() then hud:Notify("材料不足，或所有商品已锁定") end
        else
            local index=key==KEY_1 and 1 or key==KEY_2 and 2 or key==KEY_3 and 3 or key==KEY_4 and 4 or 0
            if index>0 then
                local ok,message=game:BuyShop(index)
                hud:Notify(ok and "购入成功" or message)
            end
        end
    elseif game.state=="paused" then
        if key==KEY_ESCAPE or key==KEY_P then game.state="playing" end
    elseif game.state=="playing" then
        if key==KEY_SPACE then game:Cast("dash") elseif key==KEY_J then game:Cast("whirl")
        elseif key==KEY_K then game:Cast("blade") elseif key==KEY_F then game:Cast("potion")
        elseif key==KEY_E then game:Cast("burst")
        elseif key==KEY_ESCAPE or key==KEY_P then game.state="paused" end
    end
end

function HandleDungeonRender()
    if vg then View.Draw(vg,DungeonApp.game) end
end
