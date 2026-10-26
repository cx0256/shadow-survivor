local Builds={}
Builds.Roles={
    {name="均衡者",desc="没有额外加成，适合混合武器",damage={1,1,1},hp=0,harvest=0,pickup=0},
    {name="近卫",desc="剑伤害+40%；弓与法杖伤害-20%",damage={1.4,0.8,0.8},hp=0,harvest=0,pickup=0},
    {name="游侠",desc="弓伤害+35%；剑伤害-25%；生命-20",damage={0.75,1.35,1},hp=-20,harvest=0,pickup=0},
    {name="拾荒者",desc="每波收获+12，拾取+40；所有伤害-15%",damage={0.85,0.85,0.85},hp=0,harvest=12,pickup=40},
}
---@param g table
function Builds.Apply(g)
    local role=Builds.Roles[g.role] or Builds.Roles[1]
    g.player.maxHp=g.player.maxHp+role.hp g.player.hp=g.player.maxHp
    g.player.harvest=g.player.harvest+role.harvest g.player.pickup=g.player.pickup+role.pickup
end
---@param g table
function Builds.Merge(g,index)
    if g.state~="shop" then return false end
    local w=g.loadout[index]
    if not w or w.tier>=4 then return false end
    for i,other in ipairs(g.loadout) do
        if i~=index and other.kind==w.kind and other.tier==w.tier then
            w.tier=w.tier+1 table.remove(g.loadout,i)
            g.shopRevision=g.shopRevision+1 return true
        end
    end
    return false
end
return Builds
