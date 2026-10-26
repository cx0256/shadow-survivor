-- Shared sword motion and feedback. No engine dependencies; all values use
-- arena coordinates. Rendering consumes these exact swept blade angles.
local Feel={}
Feel.HalfArc=1.30

function Feel.Init(g)
    g.melee={} g.particles={} g.sfx={} g.soundMuted=false
    g.shake=0 g.hitPulse=0 g.combo=0 g.comboTime=0
end

function Feel.Ready(e) return not e.dead and e.born>=0.5 end

function Feel.Burst(g,x,y,count,c,speed)
    -- Cosmetic randomness deliberately never consumes gameplay RNG.
    for i=1,count do
        local a=i*2.399963+g.time*3
        local v=speed*(0.55+(i%5)*0.11)
        local life=0.18+(i%4)*0.055
        g.particles[#g.particles+1]={x=x,y=y,vx=math.cos(a)*v,vy=math.sin(a)*v,
            life=life,maxLife=life,color=c,size=2+i%3}
    end
    while #g.particles>240 do table.remove(g.particles,1) end
end

function Feel.Hit(g,e,crit,source)
    local p=g.player
    local sx,sy=p.x,p.y
    local force=38
    if source then sx=source.x sy=source.y force=source.knockback or force end
    local dx,dy=e.x-sx,e.y-sy
    local len=math.max(1,math.sqrt(dx*dx+dy*dy))
    local resistance=e.kind=="boss" and 0.12 or e.elite and 0.4 or e.kind=="zombie" and 0.45 or 1
    e.kickX=e.kickX+dx/len*force*resistance*9
    e.kickY=e.kickY+dy/len*force*resistance*9
    e.stagger=math.max(e.stagger,e.kind=="boss" and 0 or 0.065)
    g.hitPulse=math.max(g.hitPulse,crit and 1 or 0.45)
    if #g.sfx<24 then g.sfx[#g.sfx+1]={kind=crit and "crit" or "hit",x=e.x} end
    if crit then g.shake=math.max(g.shake,1.6) end
    Feel.Burst(g,e.x,e.y-10,crit and 9 or 5,crit and {255,204,95} or {229,231,215},crit and 190 or 135)
end

function Feel.Death(g,e)
    g.combo=g.comboTime>0 and g.combo+1 or 1
    g.comboTime=1.6
    Feel.Burst(g,e.x,e.y-12,e.kind=="boss" and 26 or 9,
        e.kind=="bat" and {151,129,183} or {183,153,107},e.kind=="boss" and 260 or 160)
    if e.elite or e.kind=="boss" then g.shake=3 end
end

function Feel.Sword(g,w,angle,stats)
    -- Alternate direction; scale timing down with haste so a slot never has
    -- overlapping swings. Windup -> sweep -> recovery remains visible.
    w.swingIndex=(w.swingIndex or 0)+1
    local direction=w.swingIndex%2==1 and 1 or -1
    local duration=math.min(0.24,stats.cooldown*0.8)
    local swing={age=0,duration=duration,windup=duration*0.13,sweepTime=duration*0.62,
        angle=angle,halfArc=Feel.HalfArc,direction=direction,progress=0,
        bladeAngle=angle-direction*Feel.HalfArc,range=stats.range,damage=stats.damage,
        hits={},x=g.player.x,y=g.player.y,slot=w}
    w.swing=swing
    g.melee[#g.melee+1]=swing
    if #g.sfx<24 then g.sfx[#g.sfx+1]={kind="swing",x=g.player.x} end
end

function Feel.UpdateSwords(g,dt)
    for i=#g.melee,1,-1 do
        local s=g.melee[i]
        s.x=g.player.x s.y=g.player.y
        local previous=s.progress
        s.age=s.age+dt
        s.progress=math.max(0,math.min(1,(s.age-s.windup)/s.sweepTime))
        s.bladeAngle=s.angle+s.direction*(-s.halfArc+2*s.halfArc*s.progress)
        s.slot.angle=s.bladeAngle
        if s.age>=s.windup and s.progress>previous then
            local a=s.direction*(-s.halfArc+2*s.halfArc*previous)
            local b=s.direction*(-s.halfArc+2*s.halfArc*s.progress)
            local lo,hi=math.min(a,b),math.max(a,b)
            for _,e in ipairs(g.enemies) do
                if Feel.Ready(e) and not s.hits[e] then
                    local dx,dy=e.x-s.x,e.y-s.y
                    local d=math.sqrt(dx*dx+dy*dy)
                    local offset=math.atan(math.sin(math.atan(dy,dx)-s.angle),math.cos(math.atan(dy,dx)-s.angle))
                    -- Enemy circles may intersect the edge of the sector even
                    -- when their centres are just outside it.
                    local pad=math.asin(math.min(1,e.r/math.max(e.r,d)))
                    if d<=s.range+e.r and offset+pad>=lo and offset-pad<=hi
                        and g:WallFraction(s.x,s.y,e.x,e.y,2)>=1 then
                        s.hits[e]=true
                        g:DamageEnemy(e,s.damage,true,{x=s.x,y=s.y,knockback=49})
                    end
                end
            end
        end
        if s.age>=s.duration then
            if s.slot.swing==s then s.slot.swing=false end
            table.remove(g.melee,i)
        end
    end
end

function Feel.Update(g,dt)
    g.shake=math.max(0,g.shake-dt*18)
    g.hitPulse=math.max(0,g.hitPulse-dt*7)
    g.comboTime=math.max(0,g.comboTime-dt)
    if g.comboTime<=0 then g.combo=0 end
    for i=#g.particles,1,-1 do
        local p=g.particles[i]
        p.life=p.life-dt
        p.x=p.x+p.vx*dt p.y=p.y+p.vy*dt
        p.vx=p.vx*math.exp(-7*dt) p.vy=p.vy*math.exp(-7*dt)
        if p.life<=0 then table.remove(g.particles,i) end
    end
end

return Feel
