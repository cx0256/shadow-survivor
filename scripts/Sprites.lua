-- Original ember-dungeon pixel characters. Every enemy has its own silhouette,
-- equipment and two motion frames; palette values stay readable on the dark floor.
local Sprites = {
HERO = { rows = {".......cc.......","......kkkk......",".....kMMMMk.....","....kMmmmmMk....","....kMvvvvMk....","....kMvvvvMk....","....kMmmmmMk....","...kkcccccckk...","..kccCccccCcck..","..kccCccccCcck..","..kccCccccCcck..","...kcccccccck...","....kcckkcck....","....kbbk.kbbk...","....kkkk.kkkk...","................"}, palette = {
["k"]={21,16,14},
["M"]={159,171,185},
["m"]={77,87,99},
["v"]={21,26,32},
["c"]={184,52,44},
["C"]={122,30,25},
["b"]={51,41,31},
}},
HERO_B = { rows = {".......cc.......","......kkkk......",".....kMMMMk.....","....kMmmmmMk....","....kMvvvvMk....","....kMvvvvMk....","....kMmmmmMk....","...kkcccccckk...","..kccCccccCcck..","..kccCccccCcck..","..kccCccccCcck..","...kcccccccck...","....kcckkcck....","...kbbk...kbbk..","...kkkk...kkkk..","................"}, palette = {
["k"]={21,16,14},
["M"]={159,171,185},
["m"]={77,87,99},
["v"]={21,26,32},
["c"]={184,52,44},
["C"]={122,30,25},
["b"]={51,41,31},
}},
SKEL = { rows = {"................",".....kkkkkk.....","....kwwwwwwk....","....kwewwewk....","....kwwwwwwk....",".....kwkkwk.....","......kwwk......","....kkwwwwkk....","...kwwWwwWwwk...","...kwWwwwwWwk...","...kwwWwwWwwk...","....kwwwwwwk....","....kwwkkwwk....","....kwk..kwk....","....kkk..kkk....","................"}, palette = {
["k"]={20,17,16},
["w"]={216,210,192},
["W"]={143,136,122},
["e"]={42,26,26},
}},
BAT = { rows = {"................",".kk..........kk.","kppk..kkkk..kppk","kpPpkkeeeekkpppk","kppppppppppppppk","kpppppkkkkpppppk",".kppk......kppk.","..kk........kk.."}, palette = {
["k"]={26,16,24},
["p"]={138,90,122},
["P"]={77,49,69},
["e"]={255,157,157},
}},
BAT_B = { rows = {"..kk........kk..",".kppk......kppk.","kppk..kkkk..kppk","kpPpkkeeeekkpppk","kppppppppppppppk","kpppppkkkkpppppk","kppk........kppk",".kk..........kk."}, palette = {
["k"]={26,16,24},
["p"]={138,90,122},
["P"]={77,49,69},
["e"]={255,157,157},
}},
MAGE = { rows = {"................","......kkkk......",".....kuuuuk.....","....kuUuuUuk....","....kuueeuuk....","....kuuuuuuk....","...kuuUUUUuuk...","..kuuUUUUUUuuk..","..kuuUUUUUUuuk..","..kuuUUUUUUuuk..","..kuuUUUUUUuuk..","...kuuUUUUuuk...","....kuuuuuuk....","....kkkkkkkk....","................","................"}, palette = {
["k"]={20,16,30},
["u"]={138,111,216},
["U"]={74,56,120},
["e"]={196,181,253},
}},
BRUTE = { rows = {"....................","....kkkkkkkkkkkk....","...kffffffffffffk...","..kffffffffffffffk..","..kffkkffffffkkffk..","..kfkeekffffkeekfk..","..kffkkffffffkkffk..","..kffffffffffffffk..","..kfffttttttttfffk..","..kfffttttttttfffk..","..kffffffffffffffk..",".kffffFffffffFffffk.",".kffffFffffffFffffk.","kfffffFffffffFfffffk","kfffffkkkkkkkkfffffk","kffkk..........kkffk",".kkk............kkk.","...................."}, palette = {
["k"]={24,13,12},
["f"]={176,70,63},
["F"]={107,38,34},
["t"]={232,216,200},
["e"]={26,15,14},
}},
ZOMBIE = { rows = {"....................","....kkkkkkkkkkkk....","...kggggggggggggk...","..kggggggggggggggk..","..kggkkggggggkkggk..","..kgkeekggggkeekgk..","..kggkkggggggkkggk..","..kggggggggggggggk..","..kggttttttttttggk..","..kggttttttttttggk..","..kggggggggggggggk..",".kgggGggggggGggggk..",".kgggGggggggGggggk..","kggggkkkkkkkkgggggk.","kggkk........kkgggk.",".kkk..........kkkk..","...................."}, palette = {
["k"]={20,29,18},
["g"]={90,122,72},
["G"]={58,82,48},
["t"]={200,196,168},
["e"]={26,30,20},
}},
ZOMBIE_B = { rows = {"....................","....kkkkkkkkkkkk....","...kggggggggggggk...","..kggggggggggggggk..","..kggkkggggggkkggk..","..kgkeekggggkeekgk..","..kggkkggggggkkggk..","..kggggggggggggggk..","..kggttttttttttggk..","..kggttttttttttggk..","..kggggggggggggggk..","..kggGggggggGggggk..","..kggGggggggGggggk..","..kggkkkkkkkkggggk..","..kkk........kkkkk..","....................","...................."}, palette = {
["k"]={20,29,18},
["g"]={90,122,72},
["G"]={58,82,48},
["t"]={200,196,168},
["e"]={26,30,20},
}},
}

-- Pad the hand-drawn grids once, keeping frame widths fixed for mirrored drawing.
local function character(rows,palette,width)
    for i,row in ipairs(rows) do rows[i]=(row..string.rep(".",width)):sub(1,width):gsub(" ",".") end
    return {rows=rows,palette=palette}
end

local bone={k={24,25,28},b={219,210,180},B={155,148,127},i={99,123,137},I={168,188,193},
    e={245,166,91},r={125,56,44},s={58,60,64},g={190,146,74}}
local skeleton={
    ".......kkk........", ".....kkIIikk......", "....kiIIiiik......", "....kbbbBbBk......",
    "....kbekbek.......", ".....kbkbbk.......", ".....kBbbk........", "...kkkkbbkk.......",
    "..kiIikbbBbk......", "..kiIikbkbbkk.....", "...kkbkbbkBbBk....", "...kBbkBbk.kbk....",
    "...kbkkbbk.kBk....", "....kkkbbk.kk.....", "...kbBbBbBk.gk....", "...kBkbbBk..gk....",
    "....kbkBk...Ik....", "....kBkBk...Ik....", "....kbk.Bk..Ik....", "...kbbk.Bbk.ik....",
    "...kkkk.kkk.kk....", ".................."}
Sprites.SKEL=character(skeleton,bone,18)
local skelB={table.unpack(skeleton)}
skelB[18]="....kBk..Bk.Ik...." skelB[19]="...kbk...kBkIk...."
skelB[20]="..kbbk....Bbkik..." skelB[21]="..kkkk....kkkk...."
Sprites.SKEL_B=character(skelB,bone,18)

local wing={k={27,20,31},p={147,73,104},P={87,44,72},v={203,114,130},b={61,43,63},
    e={255,194,101},f={244,215,190}}
Sprites.BAT=character({
    ".kk..................kk.", "kppk................kppk", "kpvpk....k..k....kppvpk",
    "kpvPpk...kbkbk...kpPpvk", "kpvPPpk.kbebek.kpPPpvk", "kpvPPPPkkbbbbkkPPPPpvk",
    "kppvPPPPkbf fbkPPPPvppk", ".kppvPPPkbffbkPPPvppk.", "..kppvPPkbbbbkPPvppk..",
    "...kkpPkkbbbbkkPpkk...", ".....kk..kbbk..kk.....", ".........kbbk.........",
    "..........kk..........", "........................"},wing,24)
-- A real folded-wing pose instead of just shifting the same flat wing strip.
Sprites.BAT_B=character({
    "........................", ".........k..k.........", "........kbkbk........",
    "...kk..kbebek..kk...", "..kpvkkkbbbbkkkpvk..", "..kpvPPkbf fbkPPpvk..",
    "..kpvPPkbffbkPPpvk..", "..kpvPPkbbbbkPPpvk..", "..kpvPPkbbbbkPPpvk..",
    "..kpvPpkbbbbkpPpvk..", "...kpvpkbbk kpvpk...", "...kppk.kk..kppk...",
    "....kk........kk....", "........................"},wing,24)

local rot={k={24,29,25},g={108,135,77},G={64,87,52},l={158,170,103},
    e={244,198,102},r={106,50,45},c={99,76,64},C={143,120,85},b={206,193,151},s={55,57,46}}
local zombie={
    "......................", ".......kkkkkk.........", "......kgglgggk........", ".....kggkkgggGk.......",
    ".....kgekgggGGk.......", ".....kggggrrGGk.......", "......kbbgbbGkk.......", "....kkkgggGGGggkk.....",
    "...kgglggGGGggglgk....", "..kgggGlgGGgcggggGk...", "..kglggGkGGgcgGggGk...", "..kggbggkCccCkkggGk...",
    "..kgbbbgkcccck.kGGk...", "..kggbggkCccCk.kkk....", "...kggGkkccrcck.......", "....kkkkcccCcck.......",
    "......kcccCccck.......", "......kCckkkCck.......", "......kGk...kGk.......", ".....kGGk...kggk......",
    ".....kssk...kssk......", ".....kkkk...kkkk......"}
Sprites.ZOMBIE=character(zombie,rot,22)
local zombieB={table.unpack(zombie)}
zombieB[10]="..kgggGlgGGgcggggGk..." zombieB[12]="..kglbggkCccCkkggGk..."
zombieB[19]=".....kGGk....kGk......" zombieB[20]="....kGGk.....kggk....."
zombieB[21]="....kssk.....kssk....." zombieB[22]="....kkkk.....kkkk....."
Sprites.ZOMBIE_B=character(zombieB,rot,22)

local magic={k={24,22,36},u={101,75,143},U={58,45,88},h={151,119,185},
    e={156,244,220},E={222,255,236},g={186,146,80},s={85,62,45},b={39,33,48}}
local mage={
    "...........kk.........", "..........khk.........", ".........khuk.........", "........khuUk.........",
    ".......khuUUk.........", "......khuUUUkk........", ".....khhuUUUUuk.......", "....kkggggggggkk......",
    ".....kUbbbbbbUk.......", ".....kUbeebbbUk....kk.", ".....kuUbbbbUuk...keEk", "......kuUUUUuk....keek",
    ".....khuUguUuuk....kgk", "....khuUUgUUUuuk...ksk", "...khuUUUgUUUUuuk..ksk",
    "...kuUukUgUUkuuUk..ksk", "....kkkkugeUkkkk...ksk", ".....kuUUgUUUuk....ksk",
    ".....kuUUgUUUuk....ksk", "....kuUUUgUUUUuk...ksk", "....kuUUUgUUUUuk...ksk",
    "....kukkUUkkUukk...ksk", ".....kk.kk..kk......kk", "......................"}
Sprites.MAGE=character(mage,magic,22)
local mageB={table.unpack(mage)}
mageB[15]="....khuUUgUUUUuk...ksk" mageB[16]="....kuUkUgUUkuUk...ksk"
mageB[22]=".....kukkUUkkUuk...ksk" mageB[23]="......kk.kk..kk.....kk"
Sprites.MAGE_B=character(mageB,magic,22)

local hunt={k={27,23,25},i={101,115,123},I={190,203,199},b={72,55,49},B={127,99,75},
    r={182,65,47},R={235,113,68},e={255,199,106},s={47,42,43},g={183,147,80}}
local hunter={
    "......kk....kk..........", ".....kIik..kiIk.........", ".....kiIikkIiik.........", ".....kIIiiiiIIk.........",
    "......kiekiek...........", "......kiiIiiik..........", ".......kkIikk...........", "....kkkrrRrrkk..........",
    "...kBbbkrrrkkrrkk.......", "..kBbbbkbbsk..kkrrk.....", "..kbbBBkbisk....kk......", "...kBbkkbisk..kkkk......",
    "....kgkbBisk.kIIIik.....", "....kgkBBisk.kiIik......", "....kskbbBbk.kik........", "....kskkbbkkkik.........",
    "....ksk.kbkBkik.........", "....ksk.kBkBkik.........", "....ksk.kbk.Bk..........", ".....kkkBBk.BBk.........",
    ".......kkkk.kkk.........", "........................"}
Sprites.HUNTER=character(hunter,hunt,24)
local hunterB={table.unpack(hunter)}
hunterB[10]="..kBbbbkbbsk...kkrrk...." hunterB[11]="..kbbBBkbisk.....kk....."
hunterB[18]="....kskkBk..Bkik........" hunterB[19]="....kskbk...kBk........."
hunterB[20]=".....kBBk....BBk........" hunterB[21]=".....kkkk....kkk........"
Sprites.HUNTER_B=character(hunterB,hunt,24)

local iron={k={25,23,24},i={74,83,87},I={132,148,149},b={142,99,55},B={210,161,79},
    r={163,48,35},R={242,112,44},e={255,218,122},s={47,43,43},c={102,74,54}}
local boss={
    ".....kk..............kk.....", ".....kBk...kk..kk...kBk.....", ".....kBBkkkBBkkBBkkkBBk.....",
    "......kBBBBBBBBBBBBBBk......", "......kIIiiiiiiiiiIIk.......", ".......kIIiiiiiiIIk........",
    ".......kirekiikeriik........", ".......kiiikkkkiiik........", "....kkkkIikkkkIiiikkkk.....",
    "...kBIiikIIIiiIIIkiiiIBk...", "..kBBIiiikbbbbbbkiiiiIBBk..", ".kBIIiiikkbReeRbkkiiiiIBk..",
    ".kIIiiikikbReeRbikikiiiIIk.", ".kIiiik.ikbRerRbik.kiiiIIk.", ".kIiiik.ikbReeRbik.kiiiIIk.",
    ".kIIiik.ikbbBBbbik.kiiiIIk.", "..kBbbk.kiIIiiIIik.kbbBk...", "..kBbbk..kBBBBBBk..kbbBk...",
    "..kccck..kbbssbbk..kccck...", "..kccck..kIikkIIk..kccck...", "...kkk..kIIk..kIIk..kkk....",
    "........kIik..kiIk.........", ".......kIIik..kiIIk........", "......kIIIIk..kIIIIk.......",
    "......kkkkkk..kkkkkk.......", "............................"}
Sprites.BRUTE=character(boss,iron,28)
local bossB={table.unpack(boss)}
bossB[22]=".......kIIik...kiIk........" bossB[23]="......kIIik....kiIIk......."
bossB[24]=".....kIIIIk....kIIIIk......" bossB[25]=".....kkkkkk....kkkkkk......"
Sprites.BRUTE_B=character(bossB,iron,28)

return Sprites
