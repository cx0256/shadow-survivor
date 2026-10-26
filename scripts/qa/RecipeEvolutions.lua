require "main"
---@type DungeonModuleAPI
local Dungeon=require "Dungeon"
---@type SurvivorRulesAPI
local Survival=require "Survival"
---@type WeaponEvolutionsAPI
local Recipes=require "WeaponEvolutions"
DungeonApp.onReady=function()
    DungeonApp.testing=true
    local checks=0
    local function check(ok,msg) assert(ok,msg) checks=checks+1 end
    local function game(kind)
        local g=Dungeon.New({}) g:SetWeapon(kind or 1) g:Start()
        g.enemies={} g.spawnTimer=999 g.player.x=400 g.player.y=300 g.player.crit=0
        return g
    end
    local function prepared(kind)
        local g=game(kind) g.state="shop" g.waveActive=false
        g.loadout={{kind=kind,tier=2,cd=0,angle=0}}
        g.items={Recipes.Definitions[kind].item} g.forgeVouchers=1
        return g
    end
    for kind=1,3 do
        local g=prepared(kind)
        local hp,haste,gold=g.player.maxHp,g.player.haste,g.gold
        check(g:RecipeStatus(kind).canEvolve,"complete recipe offers evolution")
        check(g:EvolveWeapon(kind) and g.forgeVouchers==0 and g.weaponEvolutions[kind],"one voucher unlocks matching kind")
        check(#g.loadout==1 and g.loadout[1].tier==2 and #g.items==1,"evolution preserves weapon and relic")
        check(g.player.maxHp==hp and g.player.haste==haste and g.gold==gold,"evolution does not reapply relic mods or charge materials")
        check(not g:EvolveWeapon(kind) and #g.recipeUnlocks==1,"duplicate evolution cannot spend or duplicate reward")
        g.loadout={{kind=kind%3+1,tier=1,cd=0,angle=0}}
        check(g:RecipeStatus(kind).unlocked and g:RecipeStatus(kind).tier==0,"selling evolved kind keeps the run unlock")
        check(Survival.AddWeapon(g,kind,1) and g.weaponEvolutions[kind],"new same-kind weapons inherit the run unlock")
        g:Start()
        check(not g.weaponEvolutions[kind] and #g.recipeUnlocks==0 and g.recipeStats.cleaves==0,"restart clears recipe progression")
        g=prepared(kind) g.loadout[1].tier=1
        check(not g:EvolveWeapon(kind) and g.forgeVouchers==1,"tier I alone cannot activate a recipe")
        g=prepared(kind) g.items={}
        check(not g:EvolveWeapon(kind) and g.forgeVouchers==1,"missing relic preserves voucher")
        g=prepared(kind) g.forgeVouchers=0
        check(not g:EvolveWeapon(kind) and not g.weaponEvolutions[kind],"missing voucher prevents evolution")
        g=prepared(kind) g.state="playing"
        check(not g:EvolveWeapon(kind) and g.forgeVouchers==1,"combat cannot evolve")
    end
    local g=prepared(1)
    for _,kind in ipairs({0,4,-1,1.5,"bow",false}) do
        check(not g:EvolveWeapon(kind) and g.forgeVouchers==1,"invalid recipe kind is safe")
    end
    check(not g:EvolveWeapon(nil),"missing recipe kind is safe")
    g=prepared(1) g:EvolveWeapon(1)
    g.loadout[#g.loadout+1]={kind=2,tier=2,cd=0,angle=0}
    g.items[#g.items+1]=Recipes.Definitions[2].item g.forgeVouchers=1
    check(not g:RecipeStatus(2).canEvolve and not g:EvolveWeapon(2),"a run chooses one distinct recipe core")
    check(g.forgeVouchers==1 and #g.recipeUnlocks==1,"another complete recipe cannot consume a voucher after commitment")
    check(Survival.AddWeapon(g,3,1) and #g.loadout==3,"core choice leaves ordinary weapon mixing available")
    g.starter=2
    check(not Survival.GenerateOffer(g,1).recipeHint,"another chosen core stops unusable starter recipe supply")

    -- The guaranteed supply uses normal prices and respects existing locks.
    for kind=1,3 do
        g=game(kind) g.state="shop" g.waveActive=false g.gold=1000
        local offer=Survival.GenerateOffer(g,1)
        check(offer.type=="weapon" and offer.kind==kind and offer.recipeHint,"supply offers missing starter copy")
        g.shop={offer}
        local before=g.gold
        check(g:BuyShop(1) and g.loadout[1].tier==2 and g.gold==before-offer.cost,"supply copy must be bought and really fuses")
        offer=Survival.GenerateOffer(g,1) g.shop={offer}
        check(offer.type=="item" and offer.item.name==Recipes.Definitions[kind].item and offer.recipeHint,"supply follows into missing catalyst")
        check(g:BuyShop(1) and g:RecipeStatus(kind).itemReady,"real item purchase satisfies recipe")
        local locked={type="weapon",kind=kind,tier=1,cost=15,locked=true,sold=false}
        g.shop={locked,{type="item",item=Survival.Items[1],cost=12,locked=false,sold=false}}
        check(g:RerollShop() and g.shop[1]==locked,"recipe supply does not overwrite locked offers")
    end

    -- Same real attacks, no crit, no injected damage into the compared targets.
    for _,enabled in ipairs({false,true}) do
        g=prepared(1) if enabled then check(g:EvolveWeapon(1),"sword recipe fixture activates") end
        g.state="playing"
        local rear=g:SpawnEnemy("zombie",280,300,false) rear.hp=1000 rear.maxHp=1000
        local distant=g:SpawnEnemy("zombie",650,300,false)
        local remote=distant.hp
        for _=1,2 do g:Attack(0,g.loadout[1]) end
        check(rear.hp==1000,"two sword attacks do not release a rear cleave")
        g:Attack(0,g.loadout[1])
        check((enabled and rear.hp<1000) or (not enabled and rear.hp==1000),"third attack cleaves behind only with recipe")
        check(distant.hp==remote,"cleave cannot hit distant enemies")
        print("[RecipeScenario] "..cjson.encode({kind=1,enabled=enabled,rearDamage=1000-rear.hp,procs=g.recipeStats.cleaves}))
        if enabled then
            for _=1,20 do g:Attack(0,g.loadout[1]) end
            check(g.recipeStats.cleaves==1 and g.weaponEvolutionProgress[1]==3,"multiple slots cannot bypass cleave cooldown")
            g.runTime=0.45 g:Attack(0,g.loadout[1])
            check(g.recipeStats.cleaves==2,"stored cleave releases on next eligible sword attack")
        end
    end
    g=prepared(1) g:EvolveWeapon(1) g.state="playing" g.player.x=160 g.player.y=312
    local sheltered=g:SpawnEnemy("zombie",290,312,false) local shelterHp=sheltered.hp
    for _=1,3 do g:Attack(0,g.loadout[1]) end
    check(sheltered.hp==shelterHp,"cleave respects the side pillar")

    for _,enabled in ipairs({false,true}) do
        g=prepared(2) if enabled then check(g:EvolveWeapon(2),"bow recipe fixture activates") end
        g.state="playing"
        local targets={}
        for _,point in ipairs({{480,300},{500,355},{440,410}}) do
            local enemy=g:SpawnEnemy("zombie",point[1],point[2],false)
            enemy.hp=200 enemy.maxHp=200 targets[#targets+1]=enemy
        end
        g:Shoot("arrow",0,100,1)
        for _=1,70 do g:UpdateShots(0.034) end
        local damaged=0
        for _,enemy in ipairs(targets) do if enemy.hp<200 then damaged=damaged+1 end end
        check(damaged==(enabled and 3 or 1),"real swept arrow reaches distinct targets only through bounded ricochets")
        check(#g.shots==0 and g.recipeStats.bounces==(enabled and 2 or 0),"ricochets terminate at two extra hits")
        if enabled then check(targets[1].hp==100 and targets[2].hp==125 and targets[3].hp==144,"ricochet damage attenuates and never hits same target twice") end
        print("[RecipeScenario] "..cjson.encode({kind=2,enabled=enabled,targetsHit=damaged,bounces=g.recipeStats.bounces}))
    end
    g=prepared(2) g:EvolveWeapon(2) g.state="playing"
    local guidedTargets={}
    for _,point in ipairs({{480,300},{500,355},{440,410},{360,380}}) do
        local enemy=g:SpawnEnemy("zombie",point[1],point[2],false)
        enemy.hp=200 guidedTargets[#guidedTargets+1]=enemy
    end
    g:Shoot("arrow",0,100,2) local guided=g.shots[1]
    for _=1,90 do g:UpdateShots(0.034) end
    check(guidedTargets[1].hp==100 and guidedTargets[2].hp==100,"guided penetration preserves full damage in the original hit budget")
    check(guidedTargets[3].hp==125 and guidedTargets[4].hp==144,"two extra bounces extend the original penetration budget")
    check(guided.bounces==2 and g.recipeStats.bounces==3 and #g.shots==0,"one guided penetration plus two extra bounces remains finite")
    print("[RecipeScenario] "..cjson.encode({kind=2,enabled=true,normalPierce=2,targetsHit=4,redirects=g.recipeStats.bounces,extraBounces=guided.bounces}))
    g=prepared(2) g:EvolveWeapon(2) g.state="playing" g.player.x=160 g.player.y=312
    local previous=g:SpawnEnemy("skeleton",150,312,false)
    local blocked=g:SpawnEnemy("zombie",290,312,false)
    local warning=g:SpawnEnemy("bat",170,320,false) warning.born=-0.25
    g:Shoot("arrow",0,30,1)
    local shot=g.shots[1] shot.hits[previous]=true
    check(not Recipes.Bounce(g,shot,previous,160,312),"ricochet ignores warning enemies and targets behind walls")
    blocked.x=600 blocked.y=312
    check(not Recipes.Bounce(g,shot,previous,160,312),"ricochet cannot search beyond its range")

    for _,enabled in ipairs({false,true}) do
        g=prepared(3) if enabled then check(g:EvolveWeapon(3),"staff recipe fixture activates") end
        g.state="playing"
        local source=g:SpawnEnemy("zombie",420,300,false)
        source.hp=1 source.burnTime=0.01 source.burnDamage=100
        local targets={}
        for i=1,7 do
            local enemy=g:SpawnEnemy("zombie",430+i*7,300,false)
            enemy.hp=1000 targets[i]=enemy
        end
        targets[1].burnDamage=200 targets[1].burnTime=10
        local warning=g:SpawnEnemy("bat",425,290,false) warning.born=-0.25
        g:UpdateEnemy(source,0.034)
        check(source.dead,"final active burning frame can kill the source")
        local newlyBurning=0
        for i=2,7 do if targets[i].burnTime>0 then newlyBurning=newlyBurning+1 end end
        check(newlyBurning==(enabled and 4 or 0),"burning death spreads only to five nearest eligible enemies")
        check(targets[1].burnDamage==200 and targets[1].burnTime==10,"spread does not weaken a stronger existing flame")
        check(targets[2].hp==1000 and warning.burnTime==0,"spread is DOT setup, not instant or invisible-enemy damage")
        if enabled then check(targets[2].burnDamage==75 and targets[2].burnTime==3,"spread inherits attenuated burn for three seconds") end
        print("[RecipeScenario] "..cjson.encode({kind=3,enabled=enabled,newlyBurning=newlyBurning,spreads=g.recipeStats.spreads}))
    end
    g=prepared(3) g:EvolveWeapon(3) g.state="playing"
    local source=g:SpawnEnemy("skeleton",160,312,false)
    source.burnTime=3 source.burnDamage=20
    local shielded=g:SpawnEnemy("skeleton",265,312,false)
    g:Kill(source)
    check(shielded.burnTime==0,"spreading fire cannot cross a pillar")
    g=prepared(3) g:EvolveWeapon(3) g.state="playing"
    g.loadout={{kind=1,tier=1,cd=0,angle=0}}
    source=g:SpawnEnemy("skeleton",420,300,false) source.burnTime=3 source.burnDamage=20
    local target=g:SpawnEnemy("skeleton",450,300,false)
    g:Kill(source)
    check(target.burnTime==0,"selling all staves suspends the fire recipe until a staff is equipped again")
    local original=DungeonApp.game
    for kind=1,3 do
        g=prepared(kind) g:EvolveWeapon(kind) g.state="playing"
        g:Effect(400,300,160,"cleave") g:Effect(430,300,19,"ricochet") g:Effect(460,300,110,"spread")
        g:Shoot("arrow",0,30,1) g.shots[1].bounces=1
        DungeonApp.game=g HandleDungeonRender()
        check(true,"native draw path accepts evolved weapon effects")
    end
    DungeonApp.game=original
    print("[RecipeTests] "..checks.." recipe progression and real combat checks passed")
end
