"""Lua 5.4 simulation checks; engine/UI bindings below are test doubles.

Install lupa in a disposable location and pass --deps <directory> if needed.
This does not certify native rendering, touch delivery, or publish readiness.
"""
import argparse
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--deps')
args = parser.parse_args()
if args.deps:
    sys.path.insert(0, str(Path(args.deps).resolve()))
from lupa.lua54 import LuaRuntime

root = Path(__file__).resolve().parents[1]


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().scripts_path = (root / 'scripts' / '?.lua').as_posix()
    lua.execute('package.path = scripts_path .. ";" .. package.path; math.randomseed(20261102)')
    # Windows Lua fopen uses ANSI paths; Python reads Unicode paths for preload.
    for path in (root / 'scripts').rglob('*.lua'):
        name = path.relative_to(root / 'scripts').with_suffix('').as_posix()
        lua.execute('local name,source=...; package.preload[name]=assert(load(source,"@"..name..".lua"))',
                    name, path.read_text(encoding='utf-8-sig'))
    return lua


lua = runtime()
lua.execute('print("[ExistingSimulation]", require("qa/Simulation"))')
for module in ('Counterplay', 'CombatTrials'):
    if (root / 'scripts' / 'qa' / f'{module}.lua').exists():
        runtime().execute(f'require("qa/{module}")')
for module in ('SwordRegression', 'EnemyPressure', 'EngagementRules'):
    lua = runtime()
    lua.execute('package.loaded.main=true; DungeonApp={}; cjson={encode=function() return "{}" end}')
    lua.execute(f'require("qa/{module}"); DungeonApp.onReady()')

lua = runtime()
lua.execute(r'''
local Dungeon=require "Dungeon"
local checks=0
local function check(ok,msg) assert(ok,msg) checks=checks+1 end
local function game()
    local g=Dungeon.New({}) g:Start() g.enemies={} g.loadout={}
    g.spawnTimer=999 g.bountySpawned=true g.formationBeat=2
    return g
end
for _,fps in ipairs({15,20,30,60}) do
    local g=game() g.player.dashCd=9 g.player.invuln=10
    local x=g.player.x
    for _=1,fps*2 do g:Update(1/fps,1,0) end
    check(math.abs(g.runTime-2)<1e-8,"elapsed combat time at "..fps.." FPS")
    check(math.abs(g.waveTime-18)<1e-8,"wave timer at "..fps.." FPS")
    check(math.abs(g.player.dashCd-7)<1e-8,"cooldown at "..fps.." FPS")
    check(not g:HitsWall(g.player.x,g.player.y,g.player.r),"movement cannot tunnel at low FPS")
end
local g=game() g.waveTime=0.01 g:Update(1,0,0)
check(g.state=="shop" and g.wave==1 and g.runTime<0.04,"catch-up stops at wave end")
g.state="paused" local clock=g.runTime g:Update(5,1,0)
check(g.runTime==clock,"paused updates do not accrue combat time")

g=game() g.player.explode=1
local a=g:SpawnEnemy("bat",180,312,false)
local shielded=g:SpawnEnemy("skeleton",254,312,false)
local exposed=g:SpawnEnemy("bat",155,312,false)
g:DamageEnemy(a,1000,false)
check(exposed.dead,"unobstructed kill explosion still chains")
check(shielded.hp==shielded.maxHp,"pillar blocks kill explosion")

for _,dt in ipairs({0.016,0.034}) do
    for _,blocked in ipairs({false,true}) do
        local run=game() run.player.x=400 run.player.y=400
        if not blocked then run.pillars={} end
        local e=run:SpawnEnemy("boss",280,240,false)
        if blocked then e.x=280 e.y=280 run.player.x=140 run.player.y=320 end
        e.bossCd=0 e.stagger=0
        run:UpdateEnemy(e,dt)
        local ox,oy=e.x,e.y
        local dx,dy=e.chargeX,e.chargeY
        local reach=e.chargeDistance
        check(e.windup>0 and e.laneLocked,"boss warning locks movement")
        local crowd=run:SpawnEnemy("skeleton",e.x+1,e.y,false) crowd.speed=0
        local charged=false
        for _=1,150 do
            e.kickX=700 e.kickY=-600
            crowd.x=e.x+1 crowd.y=e.y
            run:Update(dt,0,0)
            check(math.abs((e.x-ox)*dy-(e.y-oy)*dx)<1e-7,"boss stays on warning line under knockback")
            if e.charge>0 then charged=true end
            if charged and e.charge<=0 then break end
        end
        check(charged,"boss completes windup")
        check(math.abs(e.x-ox-dx*reach)<1e-7 and math.abs(e.y-oy-dy*reach)<1e-7,"boss stops at exact predicted endpoint")
        check(not run:HitsWall(e.x,e.y,e.r),"boss endpoint is outside walls")
    end
end
print("[ReviewCombat] "..checks.." checks passed")
''')

lua = runtime()
lua.execute(r'''
-- Exercise actual HUD gating and main input handler with fake engine bindings.
local sw,sh,dpr=390,844,1
local uw,uh=390,844
graphics={GetWidth=function() return sw end,GetHeight=function() return sh end,GetDPR=function() return dpr end}
local UI={GetWidth=function() return uw end,GetHeight=function() return uh end,Init=function() end,Scale={DEFAULT=1}}
package.loaded["urhox-libs/UI"]=UI
package.loaded.CombatAudio={Init=function() end,Update=function() end,Reset=function() end}
local HUD=require "DungeonUI"
local hud={Update=function() end}
hud.CanStartMovement=HUD.CanStartMovement
hud.top={GetAbsoluteLayoutForHitTest=function() return {x=8,y=8,w=uw-16,h=80} end}
hud.bottom={GetAbsoluteLayoutForHitTest=function() return {x=8,y=uh-90,w=uw-16,h=82} end}
HUD.New=function(g) hud.game=g return hud end
fileSystem={FileExists=function() return false end}
nvgCreate=function() return {} end nvgCreateFont=function() end SubscribeToEvent=function() end
MM_FREE=0
local touches={}
input={numTouches=0,GetTouch=function(_,i) return touches[i+1] end,GetKeyDown=function() return false end}
require "main" Start() DungeonApp.testing=true DungeonApp.game:Start()
local checks=0
local function check(ok,msg) assert(ok,msg) checks=checks+1 end
local function frame() HandleDungeonUpdate("Update",{TimeStep={GetFloat=function() return 0.016 end}}) end
local function variant(value) return {GetInt=function() return value end} end
local function touchBegin(touch)
    HandleDungeonTouchBegin("TouchBegin",{TouchID=variant(touch.touchID),
        X=variant(touch.position.x),Y=variant(touch.position.y)})
end
for _,size in ipairs({{390,844,1},{780,1688,2},{1920,1080,1}}) do
    sw,sh,dpr=size[1],size[2],size[3] uw,uh=sw/dpr,sh/dpr
    check(hud:CanStartMovement(sw*0.2,sh*0.8),"lower-left blank area starts movement")
    check(not hud:CanStartMovement(sw*0.8,sh*0.8),"right side reserved for controls")
    check(not hud:CanStartMovement(sw*0.2,sh*0.2),"upper screen does not start movement")
    check(not hud:CanStartMovement(sw*0.2,sh-40*dpr),"bottom HUD cannot start movement")
    touches={{touchID=2,position={x=sw*0.8,y=sh*0.8}}} input.numTouches=1 touchBegin(touches[1]) frame()
    touches[1].position.x=sw*0.2 frame()
    check(not DungeonApp.game.touchActive,"a drag from outside the movement zone cannot become the joystick")
    touches[2]={touchID=1,position={x=sw*0.2,y=sh*0.8}}
    input.numTouches=2 touchBegin(touches[2]) frame()
    touches[2].position.x=touches[2].position.x+45*dpr frame()
    check(DungeonApp.game.touchActive and math.abs(DungeonApp.game.stickMX-1)<1e-8,"45 screen pixels gives full speed at each DPR")
    HandleDungeonFocus("InputFocus",{Focus={GetBool=function() return false end}})
    frame()
    check(not DungeonApp.game.touchActive,"focus loss clears movement even if touch records persist")
    input.numTouches=0 frame()
    touches={{touchID=1,position={x=sw*0.2,y=sh*0.8}}} input.numTouches=1 touchBegin(touches[1]) frame()
    touches[1].position.x=touches[1].position.x+45*dpr frame()
    check(DungeonApp.game.touchActive and DungeonApp.game.stickMX==1,"a new touch can move after focus loss")
    input.numTouches=0 frame()
    check(not DungeonApp.game.touchActive and DungeonApp.game.stickMX==0,"release stops stick")
end
DungeonApp.game.state="paused"
check(not hud:CanStartMovement(sw*0.2,sh*0.8),"pause blocks movement activation")
print("[ReviewInput] "..checks.." checks passed (mock bindings)")

-- A failed write truncates its destination just like opening a real FILE_WRITE handle.
FILE_READ,FILE_WRITE=0,1
local legacyPath="shadow-dungeon-v2.json"
local files={[legacyPath]="old"}
local decoded={old={runs=7,bestWave=3}}
local paths={}
local failWrite=true
local saveLogs={}
local consolePrint=print
print=function(message,...)
    if type(message)=="string" and message:find("[DungeonSave]",1,true)==1 then
        saveLogs[#saveLogs+1]=message
    end
    consolePrint(message,...)
end
cjson={encode=function(value)
    local encoded="valid-"..(#paths+1)
    decoded[encoded]=value
    return encoded
end,decode=function(value) return assert(decoded[value],"invalid JSON") end}
fileSystem.FileExists=function(_,path) return files[path]~=nil end
File=function(path,mode)
    if mode==FILE_WRITE then
        files[path]=""
        paths[#paths+1]=path
    end
    return {IsOpen=function() return true end,Close=function() end,
        ReadString=function() return files[path] end,
        WriteString=function(_,value)
            files[path]=failWrite and "partial" or value
            return not failWrite
        end}
end
Start()
DungeonApp.testing=false
check(DungeonApp.game.save.runs==7,"existing legacy save is loaded")
DungeonApp.game:Start()
DungeonApp.game:Finish(false)
frame()
check(files[legacyPath]=="old" and DungeonApp.game.saveDirty,"failed save preserves prior progress and remains pending")
check(#saveLogs==1 and saveLogs[1]:find("write_failed",1,true)~=nil,
    "the first failure leaves one diagnostic with the failed operation")
HandleDungeonFocus("InputFocus",{Focus={GetBool=function() return false end}})
check(#saveLogs==1,"consecutive failed attempts do not flood diagnostics")
DungeonApp.game:Start()
check(DungeonApp.game.save.runs==8 and DungeonApp.game.saveDirty,
    "starting another run must preserve progress queued for a save retry")
failWrite=false
for _=1,80 do frame() end
check(not DungeonApp.game.saveDirty and #paths==3,"pending save retries without rewriting healthy frames")
check(#saveLogs==2 and saveLogs[2]:find("recovered",1,true)~=nil,"successful retry leaves one recovery diagnostic")
Start()
check(DungeonApp.game.save.runs==8,"retry commits progress across restart")
DungeonApp.game:Start()
DungeonApp.game:Finish(false)
frame()
check(paths[3]~=paths[4],"completed saves alternate slots")
Start()
check(DungeonApp.game.save.runs==9,"newer slot wins on restart")
files[paths[4]]="partial"
Start()
check(DungeonApp.game.save.runs==8,"corrupt newest slot falls back to the previous generation")
DungeonApp.game:Start()
DungeonApp.game:Finish(false)
failWrite=true frame()
DungeonApp.game:Start()
failWrite=false
HandleDungeonFocus("InputFocus",{Focus={GetBool=function() return false end}})
check(DungeonApp.game.state=="paused" and not DungeonApp.game.saveDirty,
    "backgrounding pauses combat and flushes a pending save without waiting for another frame")
HandleDungeonFocus("InputFocus",{Focus={GetBool=function() return true end}})
check(DungeonApp.game.state=="paused","foregrounding keeps combat paused until the player resumes")
Start()
check(DungeonApp.game.save.runs==9,"relaunch sees the progress flushed on focus loss")
print("[ReviewSave] interrupted write, retry, reload and fallback passed (mock bindings)")
''')
print('PASS: Lua 5.4 regressions; native engine validation is separate.')
