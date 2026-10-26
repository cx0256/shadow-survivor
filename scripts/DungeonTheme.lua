-- Obsidian / engraved copper / vermilion. Shared by every game surface.
local UI=require "urhox-libs/UI"
local T={}
T.C={ink={10,15,19,255},panel={18,25,30,255},raised={25,34,39,255},
    line={66,71,68,255},gold={218,181,112,255},paper={236,230,210,255},
    muted={156,165,160,255},red={209,87,71,255},jade={111,200,167,255},blue={111,184,212,255}}
T.Tiers={"I","II","III","IV"}
T.Rarity={{153,164,160,255},{111,200,167,255},{181,150,219,255},{240,191,97,255}}
T.Weapon={T.C.gold,T.C.jade,T.C.red}

function T.Label(value,size,c,align)
    local _,newlines=tostring(value):gsub("\n","")
    return UI.Label{text=tostring(value),fontSize=size or 14,fontColor=c or T.C.paper,
        textAlign=align or "left",whiteSpace="normal",wordBreak="break-word",lineHeight=1.3,
        minHeight=newlines>0 and ((size or 14)*1.3*(newlines+1)+2) or nil,
        flexShrink=1,pointerEvents="none"}
end

function T.Button(value,action,width,id,variant)
    local primary=variant=="primary"
    return UI.Button{id=id,text=value,onClick=action,width=width or "100%",minHeight=42,height=42,
        flexShrink=1,fontSize=13,borderRadius=2,borderWidth=1,
        backgroundColor=primary and T.C.gold or T.C.raised,
        hoverBackgroundColor=primary and {239,205,144,255} or {43,53,56,255},
        pressedBackgroundColor=primary and {172,132,69,255} or T.C.ink,
        textColor=primary and T.C.ink or T.C.paper,
        borderColor=primary and T.C.gold or T.C.line,
        disabledBackgroundColor=T.C.ink,disabledTextColor=T.C.muted,
        disabledBorderColor=T.C.line}
end

function T.Panel(children,props)
    props=props or {}
    props.children=children props.padding=props.padding or 14 props.gap=props.gap or 9
    props.backgroundColor=props.backgroundColor or T.C.panel
    props.borderColor=props.borderColor or T.C.line props.borderWidth=props.borderWidth or 1
    props.borderRadius=2
    return UI.Panel(props)
end

-- Keep actions on the same baseline even when neighboring descriptions wrap.
-- Reserve the footer in normal flow; its absolute position is relative to the
-- stretched card, rather than relying on a spacer with an auto-sized parent.
function T.ActionCard(children,action,props)
    props=props or {}
    local inset=props.padding or 12
    props.paddingBottom=inset+42+(props.gap or 8)
    children[#children+1]=UI.Panel{position="absolute",left=inset,right=inset,bottom=inset,
        height=42,flexShrink=0,children={action}}
    return T.Panel(children,props)
end

function T.Row(children,props)
    props=props or {}
    props.children=children props.flexDirection="row" props.gap=props.gap or 8
    props.alignItems=props.alignItems or "center"
    -- Auto-width row text must measure intrinsically. Wrapped text without a
    -- definite width can otherwise collapse to zero in Yoga's measure pass.
    for _,child in ipairs(children) do
        if type(child.props.text)=="string" then child:SetStyle({whiteSpace="nowrap"}) end
    end
    return UI.Panel(props)
end

function T.Rule(c)
    return UI.Panel{width="100%",height=1,flexShrink=0,backgroundColor=c or T.C.line}
end

function T.Header(kicker,title,subtitle)
    return T.Row({UI.Panel{width=48,height=58,flexShrink=0,padding=4,borderColor=T.C.red,borderWidth=1,
        backgroundColor={56,27,26,255},alignItems="center",justifyContent="center",children={
            UI.Label{text="影",fontSize=27,fontColor=T.C.red,textAlign="center",whiteSpace="nowrap"}}},
        UI.Panel{flexGrow=1,flexBasis=0,gap=5,children={T.Label(kicker,10,T.C.gold),
            T.Label(title,26,T.C.paper),T.Label(subtitle,12,T.C.muted)}}},{gap=14})
end

function T.Badge(value,c)
    local name=T.Label(value,11,c or T.C.gold,"center")
    name:SetStyle({whiteSpace="nowrap",flexShrink=0})
    return UI.Panel{paddingHorizontal=8,paddingVertical=4,borderWidth=1,borderRadius=1,
        flexShrink=0,borderColor=c or T.C.line,backgroundColor=T.C.ink,children={name}}
end

function T.WeaponName(kind,tier)
    local names={"铁剑","长弓","法杖"}
    return names[kind].."  "..T.Tiers[tier]
end

return T
