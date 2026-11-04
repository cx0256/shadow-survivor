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
        T.Row({T.Badge("8 波生存"),T.Badge("6 武器槽"),T.Badge("主动闯关")},{flexWrap="wrap"}),
        T.Label("单数波追宝，双数波进入光圈封印裂隙\n完成目标开捷径：提前撤离，或留下刷材料\n翻滚躲过攻击，下一击获得 1.8 倍反击\n武器 + 遗物 + 锻造券，凑出本局进化",12,C.muted),
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
        local detail=w.detail..(i==2 and "\n拉开距离，让追兵排成一线" or "")
        local select=T.Button(g.starter==i and "◆ 已装备" or ("选用  ["..i.."]"),function() g:SetWeapon(index) hud.lastState="" end,"100%","starter-"..i)
        weaponCards[#weaponCards+1]=T.ActionCard({
            T.Badge("0"..i,T.Weapon[i]),T.Label(w.name,16,T.Weapon[i]),
            T.Label(detail,12,C.muted)
        },select,{id="starter-card-"..i,width=compact and "100%" or "31%",height=(compact and 172 or 210)+T.ButtonHeight()-42,
            flexGrow=1,flexShrink=0,padding=10,gap=8,borderColor=g.starter==i and T.Weapon[i] or C.line})
    end
    choices[#choices+1]=T.Row(weaponCards,{width="100%",flexWrap="wrap",alignItems="stretch",gap=7})
    local body=T.Row({T.Panel(intro,{id="title-intro",width=compact and "100%" or "36%",minHeight=compact and 290 or nil,borderColor=C.gold,padding=compact and 14 or 22}),
        UI.Panel{id="title-choices",width=compact and "100%" or "61%",gap=10,children=choices}},
        {alignItems="stretch",flexDirection=compact and "column" or "row",width="100%"})
    -- Row helper intentionally fixes row direction; explicitly set compact flow.
    body:SetStyle({flexDirection=compact and "column" or "row"})
    local touch=T.TouchLayout()
    local startText=touch and (Dungeon.Weapons[g.starter].name.." · 开始一局") or "签订契约 · 开始一局  [Enter]"
    return {body}, {T.Label(touch and "上滑选武器 · 左下拖动 · 自动攻击" or "WASD 移动 · 空格翻滚 · E 引燃 · Q 切换角色",T.TouchUnits(11),C.muted),
        T.Button(startText,function() g:Start() end,300,"start","primary")}
end

---@param hud table
function Screens.Shop(hud)
    local g=hud.game
    local cards={}
    local narrow=UI.GetWidth()<620
    local recipes={}
    local starterProgress,readyRecipe
    local activeRecipe=g.recipeUnlocks[1] and g:RecipeStatus(g.recipeUnlocks[1].kind)
    local function evolveRecipe(kind)
        local _,message=g:EvolveWeapon(kind)
        feedback(hud,message)
    end
    for kind=1,3 do
        local choice=kind
        local recipe=g:RecipeStatus(kind)
        local missing={}
        if not recipe.weaponReady then missing[#missing+1]="II 阶"..Dungeon.Weapons[kind].name end
        if not recipe.itemReady then missing[#missing+1]=recipe.item end
        if g.forgeVouchers<=0 then missing[#missing+1]="夺宝券 ×1" end
        local committed=#g.recipeUnlocks>=g.recipeLimit and not recipe.unlocked
        local ready=recipe.canEvolve
        if ready and (not readyRecipe or kind==g.starter) then readyRecipe=recipe end
        if kind==g.starter then
            starterProgress=recipe.name.." · 还缺 "..table.concat(missing,"、")
        end
        local state=recipe.unlocked and "◆ 本局已激活" or committed and "本局核心已确定，下局可尝试此路线"
            or (#missing>0 and ("还缺："..table.concat(missing," / ")) or "◆ 配方齐备，可以进化")
        local evolve=T.Button(recipe.unlocked and "已激活" or committed and "本局已选其他核心" or "选为本局核心 · 1 券",function()
            evolveRecipe(choice)
        end,"100%","recipe-evolve-"..kind,ready and "primary" or nil)
        evolve:SetDisabled(not ready)
        recipes[#recipes+1]=T.ActionCard({T.Label(recipe.name,16,T.Weapon[kind]),
            T.Label("II 阶"..Dungeon.Weapons[kind].name.." + "..recipe.item,11,C.muted),
            T.Label(recipe.desc,12,C.paper),T.Label(state,11,ready and C.gold or recipe.unlocked and C.jade or C.muted)},
            evolve,{id="recipe-card-"..kind,width=UI.GetWidth()>=840 and "31%" or "100%",height=240+T.ButtonHeight()-42,flexGrow=1,padding=10,gap=7,
            borderColor=recipe.unlocked and C.jade or ready and C.gold or C.line})
    end
    local recipePanel=T.Panel({section("01","选择本局进化核心 · 每局一种"),
        T.Label("II 阶武器 + 对应遗物 + 1 张夺宝券\n同类武器继承进化；基础武器仍可混搭。",12,C.muted),
        T.Row(recipes,{width="100%",flexWrap="wrap",alignItems="stretch",gap=8}),
        T.Label("持有夺宝券 ×"..g.forgeVouchers.." · 可用于配方进化或免费 I 阶武器，任选一种用途。",11,C.gold)},
        {id="weapon-recipes",width="100%",padding=12,gap=9,borderColor=C.gold})
    local quickRecipe
    if activeRecipe then
        quickRecipe=T.Panel({T.Label(activeRecipe.name.." · 本局已激活",14,C.jade),
            T.Label(activeRecipe.desc,12,C.paper)},{id="recipe-active",width="100%",borderColor=C.jade})
    elseif readyRecipe then
        local kind=readyRecipe.kind
        quickRecipe=T.Panel({T.Label("配方齐备 · "..readyRecipe.name,14,C.gold),
            T.Button("进化 · 消耗 1 张夺宝券",function() evolveRecipe(kind) end,"100%","recipe-quick-evolve","primary")},
            {width="100%",padding=8,gap=4,borderColor=C.gold})
    end
    local progressPanel=not quickRecipe and T.Panel({T.Label(starterProgress,12,C.muted)},
        {id="recipe-progress",width="100%",padding=8})
    local replacingStarter=false
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
            hud:BuyShop(index)
        end,"70%","buy-"..i,g.gold>=offer.cost and not offer.sold and "primary" or nil)
        buy:SetDisabled(offer.sold)
        local lock=T.Button(offer.locked and "◆ 锁定" or "锁定",function() g:LockOffer(index) end,"28%","lock-"..i)
        lock:SetDisabled(offer.sold)
        local starter=offer.starterDiscount and g.wave==1
        if starter and not offer.sold and not offer.locked then replacingStarter=true end
        local category=weapon and ("武器 / "..T.Tiers[offer.tier]) or "遗物 / 道具"
        local content={T.Row({T.Label(starter and (i==2 and "首波补给 · 近战" or "首波补给") or category,10,accent),
            T.Label(offer.sold and "已售出" or offer.locked and "保留至下波" or (offer.cost.." 材料"),11,offer.locked and C.gold or C.muted)},
            {justifyContent="space-between"}),T.Label(title,18,offer.sold and C.muted or C.paper)}
        if not starter then
            content[#content+1]=T.Label(detail,12,C.muted)
            content[#content+1]=T.Rule(accent)
            content[#content+1]=T.Label(statsLine,12,accent)
        end
        if not offer.sold then content[#content+1]=T.Label(outcome,11,C.muted) end
        cards[#cards+1]=T.ActionCard(content,T.Row({buy,lock},{justifyContent="space-between"}),
        {id="shop-card-"..i,width=(starter or narrow) and "100%" or "48%",minHeight=starter and 170 or narrow and 242 or 270,
            flexGrow=1,padding=12,gap=8,borderColor=offer.locked and C.gold or C.line,
            opacity=offer.sold and 0.55 or 1})
    end
    local rerollHint=T.Label(replacingStarter and "刷新会替换首波补给，锁定可保留" or "锁定的商品会跨刷新、跨波次保留",
        11,replacingStarter and C.gold or C.muted)
    local stockTitle=g.wave==1 and g.shop[2] and g.shop[2].starterDiscount and "本波补给 · 合成或补近战" or "本波补给"
    if g.wave==1 and progressPanel then
        table.insert(cards,math.min(2,#cards+1),progressPanel)
    end
    local stock={section("02",stockTitle),T.Row(cards,{flexWrap="wrap",alignItems="stretch"}),
        T.Row({rerollHint,T.Button("刷新 "..g:RerollCost().."  [R]",function()
            if not g:RerollShop() then feedback(hud,"材料不足，或所有商品已锁定") end
        end,190,"reroll")},{id="shop-reroll-row",flexWrap="wrap",alignItems="flex-start"})}
    ---@type Widget[]
    local inventory={section("03","随身武装  "..#g.loadout.." / 6"),
        T.Button(g.autoFuse and "同阶购入：合成优先 · 点击切换" or "同阶购入：扩充槽位 · 点击切换",function()
            g.autoFuse=not g.autoFuse g.shopRevision=g.shopRevision+1
        end,"100%","fusion-mode"),
        T.Label("同类同阶合成：两把总基础输出 +10%\n弓合成同时提高射速\n保留共鸣，释放 1 槽；至少保留一把武器",11,C.muted),
        T.Label("锻造券：拾取宝箱或完成裂隙封印\n宝箱不会在波末收取；撤离前记得拾取",11,C.muted)}
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
    local stockFirst=T.TouchLayout() or g.wave==1
    local sections=stockFirst and {body,recipePanel} or {recipePanel,body}
    if quickRecipe then table.insert(sections,1,quickRecipe)
    elseif g.wave>1 then table.insert(sections,1,progressPanel) end
    return sections,{T.Label("持有 "..g.gold.." 材料 · 利息最高+8 / 波",12,C.gold),
        T.Button("进入第 "..(g.wave+1).." 波  [Enter]",function() hud.message="" g:BeginWave() end,270,"next-wave","primary")}
end

---@param hud table
function Screens.Pause(hud)
    local g=hud.game
    local recipes=unlockedRecipes(g)
    return {T.Panel({T.Label("时间停在这里，阴影也会等待。",20,C.paper),
        T.Label("WASD / 方向键：移动    空格：翻滚\nJ：旋风    K：剑气    F：药水\nE：击杀蓄能后引燃，留给密集敌群\n1 / 2 / 3 / 4：商店购买    Enter：开始下一波",14,C.muted),
        T.Label("翻滚躲过实际攻击后，2 秒内的下一次武器攻击获得 1.8 倍伤害。\n单数波追宝；第 2 / 4 / 6 波进入光圈，累计站稳 2.6 秒封印裂隙。\n完成目标后，可在圈内点「撤离本波」或按 X，站稳 0.6 秒即可撤离。\n也可以留在战场继续收集材料；撤离时未拾取的宝箱会消失。",13,C.jade),
        T.Label("本局武器进化\n"..(#recipes>0 and table.concat(recipes," / ") or "尚未激活；在商店查看配方进度"),13,#recipes>0 and C.jade or C.muted),
        T.Rule(),T.Label("触屏：屏幕左下空白区域拖动移动，底部按钮施放技能。",13,C.muted),
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
    local body={T.Row(stats,{flexWrap="wrap",alignItems="stretch"}),
        T.Panel({section("01","本局武装 · "..Builds.Roles[g.role].name),T.Row(weapons,{flexWrap="wrap"}),
            T.Label("狂热 "..g.burstCount.." 次 · 夺宝 "..g.bountyKills.." 次",13,C.muted),
            T.Label("完成目标 "..(g.trialWins or 0).." 次 · 精准闪避 "..(g.perfectDodges or 0).." 次 · 捷径节省 "..math.floor(g.trialTimeSaved or 0).." 秒",13,C.jade),
            T.Rule(),T.Label("本局进化核心",14,C.paper),T.Row(recipeBadges,{flexWrap="wrap"}),
            T.Rule(),T.Label("收集的遗物",14,C.paper),T.Row(items,{flexWrap="wrap"})},{padding=18,gap=13})}
    if g.state=="dead" and g.wave==1 and g.save.bestWave<2 then
        local move=T.TouchLayout() and "左下拖动移动，怪物靠近时点翻滚。" or "方向键移动，怪物靠近时按空格翻滚。"
        table.insert(body,1,T.Panel({T.Label("再试一次",14,C.gold),
            T.Label(move.."武器会自动攻击。撑过首波，就能用保底材料升级武器。",13,C.paper)},
            {id="first-wave-retry-tip",borderColor=C.gold}))
    elseif g.state=="dead" then
        local best=g.save.bestWave
        local record=(g.newBestWave and "新纪录" or "最高纪录").." · 第 "..best.." 波"
        local nextGoal="下局目标 · 抵达第 "..(best+1).." 波"
        if best>=8 then
            nextGoal=g.save.clears==0 and "下局目标 · 击败首领或撑到计时结束" or "试试另一把武器，挑战不同进化路线"
        end
        table.insert(body,1,T.Panel({T.Label(record,14,C.gold),T.Label(nextGoal,13,C.paper)},
            {id="retry-goal",borderColor=C.gold}))
    end
    return body,
        {T.Button("返回契约选择",function() g.state="title" end,210,"back-title"),
        T.Button("再来一局  [R]",function() g:Start() end,260,"restart","primary")}
end

return Screens
