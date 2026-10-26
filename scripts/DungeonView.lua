-- Game rendering only. Menus and HUD live in DungeonUI (urhox-libs/UI).
---@class DungeonSprite
---@field rows string[]
---@field palette table<string, number[]>
---@type table<string, DungeonSprite>
local Sprites=require "Sprites"
local View={}
local function color(c,alpha) return nvgRGBA(c[1],c[2],c[3],alpha or c[4] or 255) end
local function rect(vg,x,y,w,h,c)
    nvgBeginPath(vg) nvgRect(vg,x,y,w,h) nvgFillColor(vg,color(c)) nvgFill(vg)
end
local function circle(vg,x,y,r,c)
    nvgBeginPath(vg) nvgCircle(vg,x,y,r) nvgFillColor(vg,color(c)) nvgFill(vg)
end
local function ring(vg,x,y,r,c,width)
    nvgBeginPath(vg) nvgCircle(vg,x,y,r) nvgStrokeColor(vg,color(c)) nvgStrokeWidth(vg,width or 2) nvgStroke(vg)
end
local function line(vg,x1,y1,x2,y2,c,width)
    nvgBeginPath(vg) nvgMoveTo(vg,x1,y1) nvgLineTo(vg,x2,y2)
    nvgStrokeColor(vg,color(c)) nvgStrokeWidth(vg,width or 2) nvgStroke(vg)
end
local function text(vg,x,y,value,size,c)
    nvgFontFace(vg,"dungeon") nvgFontSize(vg,size)
    nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
    nvgFillColor(vg,color(c)) nvgText(vg,x,y,tostring(value))
end

function View.Layout()
    local dpr=math.max(1,graphics:GetDPR())
    local lw,lh=graphics:GetWidth()/dpr,graphics:GetHeight()/dpr
    local scale=math.min(lw/960,lh/624)
    return {w=lw,h=lh,dpr=dpr,scale=scale,ox=(lw-960*scale)/2,oy=(lh-624*scale)/2}
end

function View.ToArena(x,y)
    local l=View.Layout()
    return (x/l.dpr-l.ox)/l.scale,(y/l.dpr-l.oy)/l.scale
end

-- Compile adjacent pixels into runs once. The richer enemy grids need fewer
-- NanoVG fills than one rectangle per pixel, even in a crowded later wave.
local spriteRuns={}
for name,s in pairs(Sprites) do
    local runs={}
    for row,pattern in ipairs(s.rows) do
        local col=1
        while col<=#pattern do
            local key=pattern:sub(col,col)
            local last=col
            while last<#pattern and pattern:sub(last+1,last+1)==key do last=last+1 end
            if s.palette[key] then runs[#runs+1]={x=col-1,y=row,w=last-col+1,c=s.palette[key]} end
            col=last+1
        end
    end
    spriteRuns[name]=runs
end

local function sprite(vg,name,x,y,size,white,flip)
    local s=Sprites[name]
    if not s then return end
    local w,h=#s.rows[1],#s.rows
    local scale=size or 2.5
    nvgSave(vg) nvgTranslate(vg,x,y)
    if flip then nvgScale(vg,-1,1) end
    for _,run in ipairs(spriteRuns[name]) do
        rect(vg,(run.x-w/2)*scale,(run.y-h)*scale,run.w*scale,scale,white and {255,240,210} or run.c)
    end
    nvgRestore(vg)
end

local function torch(vg,x,y,t)
    local flame=11+math.sin(t*11+x)*2
    nvgBeginPath(vg) nvgCircle(vg,x,y,92)
    nvgFillPaint(vg,nvgRadialGradient(vg,x,y,2,92,nvgRGBA(241,134,58,45),nvgRGBA(241,134,58,0))) nvgFill(vg)
    rect(vg,x-7,y,14,17,{47,35,27})
    rect(vg,x-5,y-2,10,flame,{205,92,42})
    rect(vg,x-3,y-6,6,flame,{255,168,68})
    rect(vg,x-1,y-3,3,6,{255,225,134})
end

function View.Room(vg,g)
    rect(vg,0,0,960,624,{10,8,8})
    for row=2,10 do
        for col=1,18 do
            local x,y=col*48,row*48
            local seed=(row*97+col*37)%13
            local base=38+seed%5
            rect(vg,x,y,47,47,{base,base-7,base-9})
            rect(vg,x,y,47,2,{56,45,38})
            rect(vg,x+46,y,2,48,{20,16,15})
            rect(vg,x,y+45,48,3,{23,18,16})
            rect(vg,x+seed+8,y+seed*2+7,3,2,{50,40,33})
            if seed%4==0 then
                line(vg,x+11,y+12,x+18,y+20,{26,22,19},1)
                line(vg,x+18,y+20,x+15,y+25,{26,22,19},1)
            end
        end
    end
    for _,wall in ipairs({{0,80,960,16},{0,528,960,18},{0,96,48,432},{912,96,48,432}}) do
        rect(vg,wall[1],wall[2],wall[3],wall[4],{22,18,18})
    end
    line(vg,48,96,912,96,{91,62,42},2)
    line(vg,48,528,912,528,{63,43,33},2)
    for _,b in ipairs(g.pillars) do
        rect(vg,b.x-4,b.y+7,b.w+12,b.h+8,{10,8,8,115})
        rect(vg,b.x,b.y,b.w,b.h,{57,47,40})
        rect(vg,b.x+3,b.y+3,b.w-6,5,{89,71,56})
        rect(vg,b.x+b.w-7,b.y+8,7,b.h-8,{32,26,23})
        rect(vg,b.x+4,b.y+b.h-8,b.w-10,7,{38,30,26})
        rect(vg,b.x+11,b.y+15,b.w-24,2,{68,54,44})
    end
    torch(vg,144,97,g.time) torch(vg,432,97,g.time)
    torch(vg,816,97,g.time) torch(vg,144,515,g.time) torch(vg,816,515,g.time)
    ring(vg,480,148,26,{64,51,42},2)
    if g.state=="playing" and g.waveTime<10 then
        ring(vg,480,148,20+math.sin(g.time*6)*3,{181,88,61,120},2)
    end

end

local enemyLooks={
    skeleton={a="SKEL",b="SKEL_B",size=2.2,cadence=9,bob=0.7},
    bat={a="BAT",b="BAT_B",size=2.3,cadence=19,bob=3.0},
    zombie={a="ZOMBIE",b="ZOMBIE_B",size=2.4,cadence=5,bob=1.5},
    mage={a="MAGE",b="MAGE_B",size=2.2,cadence=4,bob=2.5},
    hunter={a="HUNTER",b="HUNTER_B",size=2.35,cadence=12,bob=1.0},
    boss={a="BRUTE",b="BRUTE_B",size=3.0,cadence=4,bob=1.4},
}

local function drawEnemy(vg,e,g)
    local look=enemyLooks[e.kind] or enemyLooks.skeleton
    local phase=e.born*look.cadence+e.x*0.013
    local name=math.sin(phase)>0 and look.a or look.b
    local size=look.size
    local headY=e.y+5-size*#Sprites[name].rows
    nvgBeginPath(vg) nvgEllipse(vg,e.x,e.y+4,e.r+3,e.kind=="bat" and 3 or 5)
    nvgFillColor(vg,nvgRGBA(0,0,0,e.kind=="bat" and 85 or 125)) nvgFill(vg)
    if e.born<0.5 then
        -- This marks the actual ground footprint, rather than a large halo
        -- around the character's head. It never changes collision geometry.
        local radius=e.r+2
        ring(vg,e.x,e.y,radius,{223,138,99,170},1.5)
        ring(vg,e.x,e.y,radius*math.max(0.05,math.min(1,1-e.born/0.5)),{244,192,133,110},1)
        circle(vg,e.x,e.y,radius,{180,67,49,22})
        for i=0,3 do
            local a=i*math.pi/2
            line(vg,e.x+math.cos(a)*(radius+2),e.y+math.sin(a)*(radius+2),
                e.x+math.cos(a)*(radius+5),e.y+math.sin(a)*(radius+5),{211,129,92,140},1.5)
        end
        return
    end
    local bob=math.sin(phase)*look.bob
    local lift=e.kind=="bat" and 7 or e.kind=="mage" and 4 or 0
    local flip=e.x>g.player.x
    if e.kind=="hunter" and (e.windup>0 or e.charge>0) then flip=e.chargeX<0 end
    if e.kind=="hunter" and e.charge>0 then
        line(vg,e.x-e.chargeX*29,e.y-19-e.chargeY*29,e.x,e.y-19,{209,87,53,65},8)
        line(vg,e.x-e.chargeX*20,e.y-19-e.chargeY*20,e.x,e.y-19,{255,172,94,125},2)
    elseif e.kind=="mage" then
        -- A floating hem and breathing lantern identify the ranged caster.
        circle(vg,e.x+(flip and -22 or 22),e.y-28-lift+bob,5+math.sin(g.time*5),{125,236,210,30})
    elseif e.kind=="boss" then
        circle(vg,e.x,e.y-35+bob,10+math.sin(g.time*6)*1.5,{244,124,43,30})
    end
    nvgSave(vg) nvgTranslate(vg,e.x,e.y+5+bob-lift)
    if e.kind=="hunter" then
        if e.windup>0 then nvgScale(vg,1.08,0.9)
        elseif e.charge>0 then nvgRotate(vg,flip and -0.14 or 0.14) end
    end
    sprite(vg,name,0,0,size,e.hit>0,flip)
    nvgRestore(vg)
    if e.elite then
        -- The gold chevron sits above the health bar, clear of the silhouette.
        line(vg,e.x-8,headY-12-lift,e.x,headY-17-lift,{238,189,80},2)
        line(vg,e.x,headY-17-lift,e.x+8,headY-12-lift,{238,189,80},2)
    end
    if e.bounty then
        ring(vg,e.x,e.y,e.r+3,{255,210,90,180},2)
        text(vg,e.x,headY-29-lift,"携宝 "..math.ceil(e.escapeTime).."s",13,{255,218,110})
    end
    if e.burnTime>0 then circle(vg,e.x+7,e.y-16,4,{247,118,42,180}) end
    if e.hp<e.maxHp then
        local w=e.kind=="boss" and 72 or 34
        rect(vg,e.x-w/2,headY-9-lift,w,4,{31,14,14})
        rect(vg,e.x-w/2,headY-9-lift,w*math.max(0,e.hp/e.maxHp),3,e.elite and {218,171,71} or {174,65,56})
    end
    if e.windup>0 then
        local reach=e.kind=="hunter" and 235.2 or 231
        local fraction=g:WallFraction(e.x,e.y,e.x+e.chargeX*reach,e.y+e.chargeY*reach,e.r)
        local ex,ey=e.x+e.chargeX*reach*fraction,e.y+e.chargeY*reach*fraction
        line(vg,e.x,e.y,ex,ey,{230,80,60,80},e.r*1.6)
        line(vg,e.x,e.y,ex,ey,{255,152,93,200},2)
        ring(vg,e.x,e.y,e.r+3+math.sin(g.time*24),{249,114,71},2)
    end
end

local function drawPlayer(vg,g)
    local p=g.player
    if g.overdriveTime>0 then
        circle(vg,p.x,p.y-12,31,{247,171,61,35})
        ring(vg,p.x,p.y-12,31+math.sin(g.time*20)*3,{255,202,100,190},2)
    end
    nvgBeginPath(vg) nvgEllipse(vg,p.x,p.y+5,22,7) nvgFillColor(vg,nvgRGBA(0,0,0,155)) nvgFill(vg)
    if p.dashTime>0 then
        for i=1,3 do circle(vg,p.x-p.dashX*i*17,p.y-p.dashY*i*17-16,12,{95,173,209,35}) end
    end
    nvgSave(vg)
    if p.invuln>0 and math.sin(g.time*27)>0 then nvgGlobalAlpha(vg,0.5) end
    sprite(vg,p.moving and math.sin(p.walk)>0 and "HERO_B" or "HERO",p.x,p.y+6,3,p.hit>0,math.cos(p.aim)<0)
    nvgRestore(vg)
    for i,w in ipairs(g.loadout) do
        local orbit=(i-1)/math.max(1,#g.loadout)*math.pi*2+g.time*0.35
        local swinging=w.kind==1 and w.swing
        nvgSave(vg)
        if swinging then nvgTranslate(vg,p.x,p.y-10)
        else nvgTranslate(vg,p.x+math.cos(orbit)*24,p.y-14+math.sin(orbit)*18) end
        nvgRotate(vg,w.angle)
        if w.kind==1 then
            local reach=45
            if swinging then
                local s=w.swing
                reach=s.range*g:WallFraction(p.x,p.y,p.x+math.cos(w.angle)*s.range,p.y+math.sin(w.angle)*s.range,2)
            end
            rect(vg,9,-2,11,4,{116,84,47}) rect(vg,19,-3,math.max(0,reach-19),6,{164,181,190})
            rect(vg,19,-3,math.max(0,reach-19),2,{244,246,222}) rect(vg,16,-7,4,14,{196,152,76})
            if swinging then circle(vg,reach,0,3,{255,237,177,220}) end
        elseif w.kind==2 then
            line(vg,12,-18,25,0,{169,126,70},4) line(vg,25,0,12,18,{169,126,70},4)
            line(vg,12,-18,12,18,{218,222,194},1)
        else
            rect(vg,8,-2,31,4,{116,74,45}) circle(vg,38,0,7,{218,108,52}) circle(vg,38,0,3,{255,211,111})
        end
        if w.tier>1 then circle(vg,18,-8,2+w.tier,{223,190,126,160}) end
        nvgRestore(vg)
    end

end

local function drawSwordSweep(vg,g,s)
    if s.age<s.windup then return end
    local fade=1-math.max(0,(s.age-s.windup-s.sweepTime)/(s.duration-s.windup-s.sweepTime))
    local from=math.max(0,s.progress-0.42)
    local points={}
    for i=0,14 do
        local a=s.angle+s.direction*(-s.halfArc+2*s.halfArc*(from+(s.progress-from)*i/14))
        local dx,dy=math.cos(a),math.sin(a)
        local r=s.range*g:WallFraction(s.x,s.y,s.x+dx*s.range,s.y+dy*s.range,2)
        points[#points+1]={x=s.x+dx*r,y=s.y-10+dy*r,ix=s.x+dx*r*0.56,iy=s.y-10+dy*r*0.56}
    end
    nvgBeginPath(vg) nvgMoveTo(vg,points[1].x,points[1].y)
    for i=2,#points do nvgLineTo(vg,points[i].x,points[i].y) end
    for i=#points,1,-1 do nvgLineTo(vg,points[i].ix,points[i].iy) end
    nvgClosePath(vg) nvgFillColor(vg,nvgRGBA(235,198,119,math.floor(65*fade))) nvgFill(vg)
    nvgBeginPath(vg) nvgMoveTo(vg,points[1].x,points[1].y)
    for i=2,#points do nvgLineTo(vg,points[i].x,points[i].y) end
    nvgStrokeWidth(vg,4) nvgStrokeColor(vg,nvgRGBA(255,235,177,math.floor(230*fade))) nvgStroke(vg)
end

function View.Draw(vg,g)
    local layout=View.Layout()
    nvgBeginFrame(vg,layout.w,layout.h,layout.dpr)
    rect(vg,0,0,layout.w,layout.h,{8,7,7})
    nvgTranslate(vg,layout.ox,layout.oy) nvgScale(vg,layout.scale,layout.scale)
    nvgSave(vg)
    -- Subtle world-only impact motion; HUD and buttons remain stable.
    nvgTranslate(vg,math.sin(g.time*95)*g.shake,math.cos(g.time*83)*g.shake*0.65)
    View.Room(vg,g)
    nvgScissor(vg,48,96,864,432)
    for _,h in ipairs(g.hazards) do
        circle(vg,h.x,h.y-10,h.r,{215,68,58,45})
        ring(vg,h.x,h.y-10,h.r,{249,106,76,220},2)
        ring(vg,h.x,h.y-10,h.r*math.max(0,h.time/0.9),{255,182,114,200},2)
    end
    for _,d in ipairs(g.drops) do
        local pulse=math.sin(g.time*4+d.x)*2
        local c=d.kind=="heal" and {115,215,129} or {111,210,179}
        nvgSave(vg) nvgTranslate(vg,d.x,d.y-4+pulse)
        if d.treasure then
            rect(vg,-10,-8,20,16,{201,145,52}) rect(vg,-10,-8,20,4,{255,222,112})
            rect(vg,-2,-6,4,13,{255,232,158})
        elseif d.kind=="heal" then
            rect(vg,-3,-8,6,16,c) rect(vg,-8,-3,16,6,c)
        else
            nvgRotate(vg,math.pi/4)
            rect(vg,-4,-4,8,8,c) rect(vg,-1,-1,3,3,{222,246,217})
        end
        nvgRestore(vg)
    end
    for _,s in ipairs(g.melee) do drawSwordSweep(vg,g,s) end
    local entities={}
    for _,e in ipairs(g.enemies) do if not e.dead then entities[#entities+1]={y=e.y,enemy=e} end end
    entities[#entities+1]={y=g.player.y,hero=true}
    table.sort(entities,function(a,b) return a.y<b.y end)
    for _,entry in ipairs(entities) do
        if entry.hero then drawPlayer(vg,g) else drawEnemy(vg,entry.enemy,g) end
    end
    for _,s in ipairs(g.shots) do
        local angle=math.atan(s.vy,s.vx)
        nvgSave(vg) nvgTranslate(vg,s.x,s.y-10) nvgRotate(vg,angle)
        if s.kind=="arrow" then
            if s.recipeGuided or (s.bounces or 0)>0 then
                circle(vg,-3,0,11,{111,224,190,35})
                line(vg,-27,0,10,0,{121,245,206},3)
            else line(vg,-20,0,10,0,{180,218,172},2) end
            line(vg,10,0,3,-5,{237,243,201},2) line(vg,10,0,3,5,{237,243,201},2)
            line(vg,-16,0,-22,-4,{108,185,141},2)
        elseif s.kind=="fireball" then
            circle(vg,-4,0,17,{247,114,49,35}) circle(vg,0,0,9,{241,114,49}) circle(vg,2,0,4,{255,221,128})
        elseif s.kind=="blade" then
            rect(vg,-28,-12,56,24,{116,207,230,50}) rect(vg,-26,-3,52,6,{174,241,244})
        else circle(vg,0,0,9,{134,102,211,110}) circle(vg,0,0,5,{196,164,246}) end
        nvgRestore(vg)
    end
    for _,e in ipairs(g.effects) do
        local k=e.life/e.maxLife
        local c=e.kind=="heal" and {116,224,156} or e.kind=="fire" and {247,141,67}
            or e.kind=="cleave" and {245,130,123}
            or e.kind=="ricochet" and {121,245,206}
            or e.kind=="spread" and {247,141,67}
            or (e.kind=="burst" or e.kind=="evolve") and {255,211,114} or {179,215,223}
        if e.kind=="slash" then
            nvgSave(vg) nvgTranslate(vg,e.x,e.y-12) nvgRotate(vg,e.angle)
            nvgBeginPath(vg) nvgMoveTo(vg,12,-28) nvgBezierTo(vg,145,-115,145,115,12,28)
            nvgStrokeColor(vg,color(c,math.floor(k*190))) nvgStrokeWidth(vg,9*k) nvgStroke(vg) nvgRestore(vg)
        else
            ring(vg,e.x,e.y-10,e.r*(1-k*0.35),{c[1],c[2],c[3],math.floor(k*210)},5*k+1)
        end
    end
    for _,p in ipairs(g.particles) do
        local k=p.life/p.maxLife
        line(vg,p.x,p.y,p.x-p.vx*0.025,p.y-p.vy*0.025,
            {p.color[1],p.color[2],p.color[3],math.floor(255*k)},p.size*k+0.5)
    end
    for _,f in ipairs(g.floats) do
        local crit=f.text:sub(1,1)=="!"
        local size=(crit and 22 or 16)*(1+math.max(0,f.life-0.68)*1.3)
        text(vg,f.x+1,f.y+2,f.text,size,{15,12,10,180})
        text(vg,f.x,f.y,f.text,size,{f.color[1],f.color[2],f.color[3],math.floor(math.min(1,f.life*2)*255)})
    end
    nvgRestore(vg)
    if g.touchActive and g.state=="playing" then
        circle(vg,g.stickX,g.stickY,45,{165,194,215,22})
        ring(vg,g.stickX,g.stickY,45,{165,194,215,80},2)
        circle(vg,g.stickX+g.stickMX*30,g.stickY+g.stickMY*30,17,{179,215,228,135})
    end
    if g.bannerTime>0 and g.state=="playing" then
        rect(vg,290,110,380,32,{14,11,10,195}) text(vg,480,126,g.banner,17,{230,202,144})
    end
    nvgEndFrame(vg)
end

return View
