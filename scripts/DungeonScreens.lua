local UI=require "urhox-libs/UI"
local T=require "DungeonTheme"
---@type {Roles: table[], Merge: fun(g: table, index: number): boolean}
local Builds=require "Builds"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
local Screens={}
local C=T.C

---@param hud table
local function feedback(hud,message)
    hud.message=message hud.lastState=""
end

local function section(number,title)
    return T.Row({T.Badge(number,C.gold),T.Label(title,15,C.paper)})
end

---@param g table
local function unlockedRecipes(g)
    local names={}
    for kind=1,3 do
        if g.weaponEvolutions[kind] then names[#names+1]=g:RecipeStatus(kind).name end
    end
    return names
end

---@param hud table
function Screens.Title(hud)
    local g=hud.game
    local compact=UI.GetWidth()<760
    local intro={T.Label("S H A D O W   /   S U R V I V O R S",10,C.gold),
        T.Label("暗影幸存者",compact and 30 or 34,C.paper),T.Rule(C.gold),
        T.Label("带着你的武器，\n签下最后一份生存契约。",15,C.muted),
        T.Row({T.Badge("8 波生存"),T.Badge("6 武器槽"),T.Badge("5–8 分钟")},{flexWrap="wrap"}),
        T.Label("击杀蓄能，按 E 引燃密集敌群\n武器 + 遗物 + 夺宝券，凑出本局进化\n追击夺宝，拾箱后选择进化或免费武器",12,C.muted),
        T.Label("最高第 "..g.save.bestWave.." 波  ·  胜利 "..g.save.clears.." 局",12,C.gold)}
    if compact then table.remove(intro,4) end
    ---@type Widget[]
    local choices={section("01","选择契约者")}
    local roles={}
    for i,role in ipairs(Builds.Roles) do
        local index=i
        local b=T.Button((g.role==i and "◆ " or "")..role.name,function() g.role=index hud.lastState="" end,compact and "48%" or "23%","role-"..i,g.role==i and "primary" or nil)
        roles[#roles+1]=b
    end
    choices[#choices+1]=T.Row(roles,{flexWrap="wrap",gap=6})
    choices[#choices+1]=T.Label(Builds.Roles[g.role].desc,13,C.gold)
    choices[#choices+1]=section("02","选择初始武器")
    local weaponCards={}
    for i,w in ipairs(Dungeon.Weapons) do
        local index=i
        local select=T.Button(g.starter==i and "◆ 已装备" or ("选用  ["..i.."]"),function() g:SetWeapon(index) hud.lastState="" end,"100%","starter-"..i)
        weaponCards[#weaponCards+1]=T.ActionCard({
            T.Badge("0"..i,T.Weapon[i]),T.Label(w.name,16,T.Weapon[i]),
            T.Label(w.detail,12,C.muted)
        },select,{id="starter-card-"..i,width=compact and "100%" or "31%",height=compact and 172 or 210,
            flexGrow=1,flexShrink=0,padding=10,gap=8,borderColor=g.starter==i and T.Weapon[i] or C.line})
    end
    choices[#choices+1]=T.Row(weaponCards,{width="100%",flexWrap="wrap",alignItems="stretch",gap=7})
    local body=T.Row({T.Panel(intro,{width=compact and "100%" or "36%",borderColor=C.gold,padding=compact and 14 or 22}),
        UI.Panel{width=compact and "100%" or "61%",gap=10,children=choices}},
        {alignItems="stretch",flexDirection=compact and "column" or "row",width="100%"})
    -- Row helper intentionally fixes row direction; explicitly set compact flow.
    body:SetStyle({flexDirection=compact and "column" or "row"})
    return {body}, {T.Label("WASD 移动 · 空格翻滚 · E 引燃 · Q 切换角色",11,C.muted),
        T.Button("签订契约 · 开始一局  [Enter]",function() g:Start() end,300,"start","primary")}
end

---@param hud table
function Screens.Shop(hud)
    local g=hud.game
    local cards={}
    local narrow=UI.GetWidth()<620
    local recipes={}
    for kind=1,3 do
        local choice=kind
        local recipe=g:RecipeStatus(kind)
        local missing={}
        if not recipe.weaponReady then missing[#missing+1]="II 阶"..Dungeon.Weapons[kind].name end
        if not recipe.itemReady then missing[#missing+1]=recipe.item end
        if g.forgeVouchers<=0 then missing[#missing+1]="夺宝券 ×1" end
        local committed=#g.recipeUnlocks>=g.recipeLimit and not recipe.unlocked
        local ready=recipe.canEvolve and g.forgeVouchers>0 and not recipe.unlocked
        local state=recipe.unlocked and "◆ 本局已激活" or committed and "本局核心已确定，下局可尝试此路线"
            or (#missing>0 and ("还缺："..table.concat(missing," / ")) or "◆ 配方齐备，可以进化")
        local evolve=T.Button(recipe.unlocked and "已激活" or committed and "本局已选其他核心" or "选为本局核心 · 1 券",function()
            local _,message=g:EvolveWeapon(choice)
            feedback(hud,message)
        end,"100%","recipe-evolve-"..kind,ready and "primary" or nil)
        evolve:SetDisabled(not ready)
        recipes[#recipes+1]=T.Panel({T.Label(recipe.name,16,T.Weapon[kind]),
            T.Label("II 阶"..Dungeon.Weapons[kind].name.." + "..recipe.item,11,C.muted),
            T.Label(recipe.desc,12,C.paper),T.Label(state,11,ready and C.gold or recipe.unlocked and C.jade or C.muted),
            evolve},{id="recipe-card-"..kind,width=UI.GetWidth()>=840 and "31%" or "100%",flexGrow=1,padding=10,gap=7,
            borderColor=recipe.unlocked and C.jade or ready and C.gold or C.line})
    end
    local recipePanel=T.Panel({section("01","选择本局进化核心 · 每局一种"),
        T.Label("II 阶武器 + 对应遗物 + 1 张夺宝券\n同类武器继承进化；基础武器仍可混搭。",12,C.muted),
        T.Row(recipes,{width="100%",flexWrap="wrap",alignItems="stretch",gap=8}),
        T.Label("持有夺宝券 ×"..g.forgeVouchers.." · 可用于配方进化或免费 I 阶武器，任选一种用途。",11,C.gold)},
        {id="weapon-recipes",width="100%",padding=12,gap=9,borderColor=C.gold})
    for i,offer in ipairs(g.shop) do
        local index=i
        local weapon=offer.type=="weapon" and Dungeon.Weapons[offer.kind] or false
        local accent=weapon and T.Rarity[offer.tier] or C.blue
        local detail=weapon and weapon.detail or offer.item.desc
        if offer.recipeHint then detail="◆ 配方补给 · "..detail end
        local title=weapon and T.WeaponName(offer.kind,offer.tier) or offer.item.name
        local statsLine="局内道具 · 购买后即刻生效"
        local outcome=""
        if weapon then
            local stats=g:WeaponStats({kind=offer.kind,tier=offer.tier})
            statsLine=string.format("伤害 %.0f   /   间隔 %.2fs   /   射程 %.0f",stats.damage,stats.cooldown,stats.range)
            local merge=false
            if g.autoFuse then
                for _,w in ipairs(g.loadout) do
                    if w.kind==offer.kind and w.tier==offer.tier and w.tier<4 then
                        local fused=g:WeaponStats({kind=offer.kind,tier=w.tier+1})
                        statsLine=string.format("合成后 伤害 %.0f / 间隔 %.2fs / 射程 %.0f",fused.damage,fused.cooldown,fused.range)
                        outcome="合成至 "..T.Tiers[w.tier+1].." 阶 · 两把总基础输出 +10% · 共鸣保留" merge=true break
                    end
                end
            end
            if not merge then outcome=#g.loadout<6 and "购买后占用 1 个武器槽" or "武器槽已满：先合成或回收" end
        end
        local buyText=offer.sold and "已购入" or g.gold<offer.cost and ("还差 "..(offer.cost-g.gold).." 材料") or ("购买 "..offer.cost.."  ["..i.."]")
        local buy=T.Button(buyText,function()
            local ok,msg=g:BuyShop(index)
            feedback(hud,ok and ("已购入："..title) or msg)
        end,"70%","buy-"..i,g.gold>=offer.cost and not offer.sold and "primary" or nil)
        buy:SetDisabled(offer.sold)
        local lock=T.Button(offer.locked and "◆ 锁定" or "锁定",function() g:LockOffer(index) end,"28%","lock-"..i)
        lock:SetDisabled(offer.sold)
        cards[#cards+1]=T.ActionCard({
            T.Row({T.Label(weapon and ("武器 / "..T.Tiers[offer.tier]) or "遗物 / 道具",10,accent),
                T.Label(offer.sold and "SOLD" or offer.locked and "保留至下波" or (offer.cost.." 材料"),11,offer.locked and C.gold or C.muted)},
                {justifyContent="space-between"}),
            T.Label(title,18,offer.sold and C.muted or C.paper),T.Label(detail,12,C.muted),
            T.Rule(accent),T.Label(statsLine,12,accent),T.Label(outcome,11,C.muted)
        },T.Row({buy,lock},{justifyContent="space-between"}),
        {id="shop-card-"..i,width=narrow and "100%" or "48%",minHeight=narrow and 242 or 270,
            flexGrow=1,padding=12,gap=8,borderColor=offer.locked and C.gold or C.line,
            opacity=offer.sold and 0.55 or 1})
    end
    local stock={section("02","本波补给"),T.Row(cards,{flexWrap="wrap",alignItems="stretch"}),
        T.Row({T.Button("刷新 "..g:RerollCost().."  [R]",function()
            if not g:RerollShop() then feedback(hud,"材料不足，或所有商品已锁定") end
        end,190,"reroll"),T.Label("锁定的商品会跨刷新、跨波次保留",11,C.muted)},{flexWrap="wrap"})}
    ---@type Widget[]
    local inventory={section("03","随身武装  "..#g.loadout.." / 6"),
        T.Button(g.autoFuse and "同阶购入：合成优先 · 点击切换" or "同阶购入：扩充槽位 · 点击切换",function()
            g.autoFuse=not g.autoFuse g.shopRevision=g.shopRevision+1
        end,"100%","fusion-mode"),
        T.Label("同类同阶合成：两把总基础输出 +10%\n弓合成同时提高射速\n保留共鸣，释放 1 槽；至少保留一把武器",11,C.muted),
        T.Label("夺宝：实战中拾起宝箱获得锻造券\n波末不会收取宝箱，记得及时靠近拾取",11,C.muted)}
    if g.forgeVouchers>0 then
        ---@type Widget[]
        local forge={T.Label("夺宝锻造券 ×"..g.forgeVouchers,14,C.gold),
            T.Label("每券任选一把 I 阶武器；同阶按当前模式合成\n与配方进化共用券，也可留到本局后续波次",11,C.muted)}
        for kind,weapon in ipairs(Dungeon.Weapons) do
            local choice=kind
            forge[#forge+1]=T.Button("免费选取 · "..weapon.name..(kind==g.starter and "（初始）" or ""),function()
                local _,message=g:ClaimForge(choice)
                feedback(hud,message)
            end,"100%","forge-claim-"..kind,kind==g.starter and "primary" or nil)
        end
        inventory[#inventory+1]=T.Panel(forge,{padding=10,gap=8,borderColor=C.gold})
    end
    for i,w in ipairs(g.loadout) do
        local index=i
        local sell=T.Button("回收",function()
            if not g:SellWeapon(index) then feedback(hud,"至少保留一把武器") end
        end,"48%","sell-"..i)
        sell:SetDisabled(#g.loadout<=1)
        local canMerge=false
        for j,other in ipairs(g.loadout) do if j~=i and other.kind==w.kind and other.tier==w.tier and w.tier<4 then canMerge=true break end end
        local merge=T.Button("合成",function()
            feedback(hud,Builds.Merge(g,index) and "合成成功：两把总基础输出 +10%，保留共鸣，空出 1 槽" or "需要同类同阶武器，最高 IV 阶")
        end,"48%","merge-"..i)
        merge:SetDisabled(not canMerge)
        inventory[#inventory+1]=T.Panel({T.Label(T.WeaponName(w.kind,w.tier),14,T.Weapon[w.kind]),
            T.Row({sell,merge},{justifyContent="space-between"})},{padding=9,gap=7})
    end
    local p=g.player
    inventory[#inventory+1]=T.Label(string.format("攻击 %d  /  护甲 %d\n伤害 %+.0f%%  /  攻速 %+.0f%%\n收获 %d  /  暴击 %.0f%%",p.atk,p.def,(p.damage-1)*100,(p.haste-1)*100,p.harvest,p.crit*100),12,C.muted)
    inventory[#inventory+1]=T.Label("共鸣：I=1 / II=2 / III=4 / IV=8\n每类最多计 6 点；合成保留共鸣\n剑 2/4/6 点：攻速 +20/35/50%\n弓 3 点：多穿透 1 敌\n杖每 2 点：灼烧 +4/秒",11,C.muted)
    local wide=UI.GetWidth()>=840
    local body=T.Row({UI.Panel{width=wide and "65%" or "100%",gap=12,children=stock},
        T.Panel(inventory,{width=wide and "33%" or "100%",padding=12,gap=8})},
        {alignItems="stretch",width="100%"})
    body:SetStyle({flexDirection=wide and "row" or "column"})
    return {recipePanel,body},{T.Label("持有 "..g.gold.." 材料 · 利息最高+8 / 波",12,C.gold),
        T.Button("进入第 "..(g.wave+1).." 波  [Enter]",function() hud.message="" g:BeginWave() end,270,"next-wave","primary")}
end

---@param hud table
function Screens.Reward(hud)
    local g=hud.game
    local cards={}
    for i,choice in ipairs(g.choices) do
        local index=i
        local choose=T.Button("选择此强化  ["..i.."]",function() g:ChooseTalent(index) end,"100%","talent-"..i,"primary")
        cards[#cards+1]=T.ActionCard({T.Label("0"..i.."  /  属性强化",11,C.jade),
            T.Label(choice.name,22,C.paper),T.Rule(C.jade),T.Label(choice.desc,14,C.muted),
            T.Label("本局永久生效",11,C.jade)
        },choose,{id="talent-card-"..i,width=UI.GetWidth()>=850 and "31%" or "100%",minHeight=246,
            flexGrow=1,padding=18,gap=13,borderColor=C.jade})
    end
    return {T.Row(cards,{flexWrap="wrap",alignItems="stretch"})},
        {T.Label("剩余 "..g.pendingLevels.." 次升级选择",12,C.muted)}
end

---@param hud table
function Screens.Pause(hud)
    local g=hud.game
    local recipes=unlockedRecipes(g)
    return {T.Panel({T.Label("时间停在这里，阴影也会等待。",20,C.paper),
        T.Label("WASD / 方向键：移动    空格：翻滚\nJ：旋风    K：剑气    F：药水\nE：击杀蓄能后引燃，留给密集敌群\n1 / 2 / 3：选择奖励    Enter：开始下一波",14,C.muted),
        T.Label("本局武器进化\n"..(#recipes>0 and table.concat(recipes," / ") or "尚未激活；在商店查看配方进度"),13,#recipes>0 and C.jade or C.muted),
        T.Rule(),T.Label("触屏：战场左下拖动移动，底部按钮施放技能。",13,C.muted),
        T.Button(g.soundMuted and "开启音效  [M]" or "关闭音效  [M]",function()
            g.soundMuted=not g.soundMuted hud.lastState=""
        end,260,"pause-audio")},{padding=22,gap=16})},
        {T.Button("结算并结束本局",function() g:Finish(false) end,210,"abandon"),
        T.Button("回到战场  [Esc / P]",function() g.state="playing" end,260,"resume","primary")}
end

---@param hud table
function Screens.Result(hud)
    local g=hud.game
    local stats={}
    for _,pair in ipairs({{"波次",g.wave.." / 8"},{"击杀",g.kills},{"材料",g.earnedGold},{"战斗时间",math.floor(g.runTime).."s"}}) do
        stats[#stats+1]=T.Panel({T.Label(pair[1],11,C.muted),T.Label(pair[2],27,C.gold)},
            {width="23%",flexGrow=1,padding=13})
    end
    local weapons={}
    for _,w in ipairs(g.loadout) do weapons[#weapons+1]=T.Badge(T.WeaponName(w.kind,w.tier),T.Weapon[w.kind]) end
    local counts={}
    for _,name in ipairs(g.items) do counts[name]=(counts[name] or 0)+1 end
    local items={}
    for name,n in pairs(counts) do items[#items+1]=T.Badge(name..(n>1 and (" ×"..n) or ""),C.muted) end
    local recipes=unlockedRecipes(g)
    ---@type Widget[]
    local recipeBadges={}
    for _,name in ipairs(recipes) do recipeBadges[#recipeBadges+1]=T.Badge(name,C.jade) end
    if #recipeBadges==0 then recipeBadges[1]=T.Label("尚未激活配方进化",12,C.muted) end
    return {T.Row(stats,{flexWrap="wrap",alignItems="stretch"}),
        T.Panel({section("01","本局武装 · "..Builds.Roles[g.role].name),T.Row(weapons,{flexWrap="wrap"}),
            T.Label("狂热 "..g.burstCount.." 次 · 夺宝 "..g.bountyKills.." 次",13,C.muted),
            T.Rule(),T.Label("本局进化核心",14,C.paper),T.Row(recipeBadges,{flexWrap="wrap"}),
            T.Rule(),T.Label("收集的遗物",14,C.paper),T.Row(items,{flexWrap="wrap"})},{padding=18,gap=13})},
        {T.Button("返回契约选择",function() g.state="title" end,210,"back-title"),
        T.Button("再来一局  [R]",function() g:Start() end,260,"restart","primary")}
end

return Screens
