-- A small reusable pool prevents dense hits from creating unbounded sources.
local Audio={}
---@type Scene|nil
local audioScene=nil
---@type SoundSource[]
local sources={}
---@type table<string, Sound>
local sounds={}
local last={swing=-10,hit=-10,crit=-10}
local cursor=0

function Audio.Init()
    audioScene=Scene()
    for i=1,8 do
        local source=audioScene:CreateChild("combat-sfx-"..i):CreateComponent("SoundSource")
        ---@cast source SoundSource
        source:SetSoundType(SOUND_EFFECT)
        sources[i]=source
    end
    sounds={
        swing=cache:GetResource("Sound","audio/combat/swing.wav"),
        hit=cache:GetResource("Sound","audio/combat/hit.wav"),
        crit=cache:GetResource("Sound","audio/combat/crit.wav"),
    }
end

function Audio.Update(g)
    if g.soundMuted or g.state~="playing" then
        for _,source in ipairs(sources) do source:Stop() end
        g.sfx={}
        return
    end
    for _,event in ipairs(g.sfx) do
        local kind=event.kind
        local gap=kind=="swing" and 0.075 or 0.045
        local sound=sounds[kind]
        if sound and g.runTime-last[kind]>=gap then
            last[kind]=g.runTime
            cursor=cursor%#sources+1
            sources[cursor]:Play(sound,0,kind=="swing" and 0.22 or kind=="crit" and 0.38 or 0.27,
                math.max(-0.65,math.min(0.65,(event.x-g.player.x)/400)))
        end
    end
    g.sfx={}
end

function Audio.Reset()
    last={swing=-10,hit=-10,crit=-10}
end

function Audio.Stop()
    for _,source in ipairs(sources) do source:Stop() end
    sources={} sounds={}
    if audioScene then audioScene:RemoveAllChildren() audioScene=nil end
end

return Audio
