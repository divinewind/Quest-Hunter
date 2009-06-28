#!/usr/bin/lua

-- I don't know why print is giving me so much trouble, but it is, sooooo
print = function (...)
  local pad = ""
  for i = 1, select("#", ...) do
    io.stdout:write(pad)
    local tst = tostring(select(i, ...))
    pad = (" "):rep(#tst - math.floor(#tst / 6) * 6 + 4)
    io.stdout:write(tst)
  end
  io.stdout:write("\n")
end

local do_zone_map = false
local do_errors = true

local do_compile = true
local do_questtables = true
local do_flight = true

local do_compress = true
local do_serialize = true

local dbg_data = false

--local s = 1048
--local e = 1048
--local e = 1000

require("luarocks.require")
require("persistence")
require("compile_chain")
require("compile_debug")
require("bit")
require("pluto")
require("gzio")
  

ll, err = package.loadlib("/nfs/build/libcompile_core.so", "init")
if not ll then print(err) return end
ll()


-- we pretend to be WoW
local LZW
local Merger
local Bitstream

do
  local world = {}
  world.QuestHelper_File = {}
  world.QuestHelper_Loadtime = {}
  world.GetTime = function() return 0 end
  world.QuestHelper = { Assert = function (self, ...) assert(...) end, CreateTable = function() return {} end, ReleaseTable = function() end }
  world.string = string
  world.table = table
  world.assert = assert
  world.bit = {mod = function(a, b) return a - math.floor(a / b) * b end, lshift = bit.lshift, rshift = bit.rshift, band = bit.band}
  world.math = math
  world.strbyte = string.byte
  world.strchar = string.char
  world.pairs = pairs
  world.ipairs = ipairs
  world.print = function(...) print(...) end
  world.QH_Timeslice_Yield = function() end
  setfenv(loadfile("../questhelper/collect_merger.lua"), world)()
  setfenv(loadfile("../questhelper/collect_bitstream.lua"), world)()
  setfenv(loadfile("../questhelper/collect_lzw.lua"), world)()
  local api = {}
  world.QH_Collect_Merger_Init(nil, api)
  world.QH_Collect_Bitstream_Init(nil, api)
  world.QH_Collect_LZW_Init(nil, api)
  LZW = api.Utility_LZW
  Merger = api.Utility_Merger
  Bitstream = api.Utility_Bitstream
  assert(Merger.Add)
end


local Astrolabe

local QuestHelper_IndexLookup
local QuestHelper_ZoneLookup

do
  local world = {}
  local cropy = {
    "string",
    "tonumber",
    "print",
    "setmetatable",
    "type",
    "table",
    "tostring",
    "error",
    "math",
    "coroutine",
    "pairs",
    "ipairs",
    "select",
  }
  for _, v in ipairs(cropy) do
    world[v] = _G[v]
  end
  world.getfenv = function (x) assert(x == 0 or not x) return world end
  
  
  world._G = world
  world.GetPlayerFacing = function () return 0 end
  world.MinimapCompassTexture = {GetTexCoord = function() return 0, 1 end}
  world.CreateFrame = function () return {Hide = function () end, SetParent = function () end, UnregisterAllEvents = function () end, RegisterEvent = function () end, SetScript = function () end} end
  world.GetMapContinents = function () return "Kalimdor", "Eastern Kingdoms", "Outland", "Northrend" end
  world.GetMapZones = function (z)
    local db = {
      {"Ashenvale", "Azshara", "Azuremyst Isle", "Bloodmyst Isle", "Darkshore", "Darnassus", "Desolace", "Durotar", "Dustwallow Marsh", "Felwood", "Feralas", "Moonglade", "Mulgore", "Orgrimmar", "Silithus", "Stonetalon Mountains", "Tanaris", "Teldrassil", "The Barrens", "The Exodar", "Thousand Needles", "Thunder Bluff", "Un'Goro Crater", "Winterspring"},
      {"Alterac Mountains", "Arathi Highlands", "Badlands", "Blasted Lands", "Burning Steppes", "Deadwind Pass", "Dun Morogh", "Duskwood", "Eastern Plaguelands", "Elwynn Forest", "Eversong Woods", "Ghostlands", "Hillsbrad Foothills", "Ironforge", "Isle of Quel'Danas", "Loch Modan", "Redridge Mountains", "Searing Gorge", "Silvermoon City", "Silverpine Forest", "Stormwind City", "Stranglethorn Vale", "Swamp of Sorrows", "The Hinterlands", "Tirisfal Glades", "Undercity", "Western Plaguelands", "Westfall", "Wetlands"},
      {"Blade's Edge Mountains", "Hellfire Peninsula", "Nagrand", "Netherstorm", "Shadowmoon Valley", "Shattrath City", "Terokkar Forest", "Zangarmarsh"},
      {"Borean Tundra", "Crystalsong Forest", "Dalaran", "Dragonblight", "Grizzly Hills", "Howling Fjord", "Icecrown", "Sholazar Basin", "The Storm Peaks", "Wintergrasp", "Zul'Drak"},
    }
    return unpack(db[z])
  end
  
  local tc, tz
  world.SetMapZoom = function (c, z) tc, tz = c, z end
  world.GetMapInfo = function ()
    local db = {
      {"Ashenvale", "Aszhara", "AzuremystIsle", "BloodmystIsle", "Darkshore", "Darnassis", "Desolace", "Durotar", "Dustwallow", "Felwood", "Feralas", "Moonglade", "Mulgore", "Ogrimmar", "Silithus", "StonetalonMountains", "Tanaris", "Teldrassil", "Barrens", "TheExodar", "ThousandNeedles", "ThunderBluff", "UngoroCrater", "Winterspring", [0] = "Kalimdor"},
      {"Alterac", "Arathi", "Badlands", "BlastedLands", "BurningSteppes", "DeadwindPass", "DunMorogh", "Duskwood", "EasternPlaguelands", "Elwynn", "EversongWoods", "Ghostlands", "Hilsbrad", "Ironforge", "Sunwell", "LochModan", "Redridge", "SearingGorge", "SilvermoonCity", "Silverpine", "Stormwind", "Stranglethorn", "SwampOfSorrows", "Hinterlands", "Tirisfal", "Undercity", "WesternPlaguelands", "Westfall", "Wetlands", [0] = "Azeroth"},
      {"BladesEdgeMountains", "Hellfire", "Nagrand", "Netherstorm", "ShadowmoonValley", "ShattrathCity", "TerokkarForest", "Zangarmarsh", [0] = "Expansion01"},
      {"BoreanTundra", "CrystalsongForest", "Dalaran", "Dragonblight", "GrizzlyHills", "HowlingFjord", "IcecrownGlacier", "SholazarBasin", "TheStormPeaks", "LakeWintergrasp", "ZulDrak", [0] = "Northrend"},
    }
    
    return db[tc][tz]
  end
  world.IsLoggedIn = function () end
  
  world.QuestHelper_File = {}
  world.QuestHelper_Loadtime = {}
  world.GetTime = function() return 0 end
  world.QuestHelper = { Assert = function (self, ...) assert(...) end, CreateTable = function() return {} end, ReleaseTable = function() end, TextOut = function(qh, ...) print(...) end }
  
  setfenv(loadfile("../questhelper/AstrolabeQH/DongleStub.lua"), world)()
  setfenv(loadfile("../questhelper/AstrolabeQH/AstrolabeMapMonitor.lua"), world)()
  setfenv(loadfile("../questhelper/AstrolabeQH/Astrolabe.lua"), world)()
  setfenv(loadfile("../questhelper/upgrade.lua"), world)()
  
  world.QuestHelper.Astrolabe = world.DongleStub("Astrolabe-0.4-QuestHelper")
  Astrolabe = world.QuestHelper.Astrolabe
  assert(Astrolabe)
  
  world.QuestHelper_BuildZoneLookup()
  
  QuestHelper_IndexLookup = world.QuestHelper_IndexLookup
  QuestHelper_ZoneLookup = world.QuestHelper_ZoneLookup
end

-- LuaSrcDiet embedding
local Diet

do
  local world = {arg = {}}
  world.string = string
  world.table = table
  world.pcall = pcall
  world.print = print
  world.ipairs = ipairs
  world.TEST = true
  setfenv(loadfile("LuaSrcDiet.lua"), world)()
  world.TEST = false
  world.error = error
  world.tonumber = tonumber
  
  local files = {input = {}, output = {}}
  
  local function readgeneral(target)
    local rv = target[target.cline]
    target.cline = target.cline + 1
    return rv
  end
  
  world.io = {
    open = function(fname, typ)
      if fname == "input" then
        assert(typ == "rb")
        return {
          read = function(_, wut)
            assert(wut == "*l")
            return readgeneral(files.input)
          end,
          close = function() end
        }
      elseif fname == "output" then
      
        if typ == "wb" then
          return {
            write = function(_, wut, nilo)
              assert(not nilo)
              assert(not files.output_beta)
              Merger.Add(files.output, wut)
            end,
            close = function() end
          }
        elseif typ == "rb" then
          files.output_beta = {}
          for k in Merger.Finish(files.output):gmatch("[^\n]*") do
            table.insert(files.output_beta, k)
          end
          files.output_beta.cline = 1
          
          return {
            read = function(_, wut)
              assert(wut == "*l")
              return readgeneral(files.output_beta)
            end,
            close = function() end
          }
        else
          assert()
        end
        
      end
    end,
    close = function() end,
    stdout = io.stdout,
  }
  
  Diet = function(inp)
    world.arg = {"input", "-o", "output", "--quiet", "--maximum"}
    files.input = {}
    for k in inp:gmatch("[^\n]*") do
      table.insert(files.input, k)
    end
    files.input.cline = 1
    files.output = {}
    files.output_beta = nil
    
    local ok = pcall(world.main)
    if not ok then return end
    
    return Merger.Finish(files.output)
  end
  
  --assert(Diet("   q    = 15 ") == "q=15")
  --assert(Diet("   jbx    = 15 ") == "jbx=15")
  --return
end


ChainBlock_Init("/nfs/build", "compile.lua", function () 
  os.execute("rm -rf intermed")
  os.execute("mkdir intermed")

  os.execute("rm -rf final")
  os.execute("mkdir final") end, ...)

math.umod = function (val, med)
  if val < 0 then
    return math.mod(val + math.ceil(-val / med + 10) * med, med)
  else
    return math.mod(val, med)
  end
end

local zone_image_chunksize = 1024
local zone_image_descale = 4
local zone_image_outchunk = zone_image_chunksize / zone_image_descale

local zonecolors = {}

--[[
*****************************************************************
Utility functions
]]

local function version_parse(x)
  if not x then return end
  
  local rv = {}
  for t in x:gmatch("[%d]+") do
    table.insert(rv, tonumber(t))
  end
  return rv
end

local function sortversion(a, b)
  local ap, bp = version_parse(a), version_parse(b)
  if not ap and not bp then return false end
  if not ap then return false end
  if not bp then return true end
  for x = 1, #ap do
    if ap[x] ~= bp[x] then
      return ap[x] > bp[x]
    end
  end
  return false
end

local function tablesize(tab)
  local ct = 0
  for _, _ in pairs(tab) do
    ct = ct + 1
  end
  return ct
end

local function loc_version(ver)
  local major = ver:match("([0-9])%..*")
  if major == "0" then
    return sortversion("0.96", ver) and 0 or 1
  elseif major == "1" then
    return sortversion("1.0.2", ver) and 0 or 1
  else
    assert()
  end
end

local function convert_loc(loc, locale)
  if not loc then return end
  assert(locale)
  if locale ~= "enUS" then return end -- arrrgh, to be fixed eventually
  
  local lr = loc.relative
  if loc.relative then
    loc.c, loc.x, loc.y = Astrolabe:GetAbsoluteContinentPosition(loc.rc, loc.rz, loc.x, loc.y)
    loc.relative = false
  end
  
  if not loc.c or not QuestHelper_IndexLookup[loc.rc] then return end
  
  if not QuestHelper_IndexLookup[loc.rc] or not QuestHelper_IndexLookup[loc.rc][loc.rz] then
    print(loc.c, loc.rc, loc.rz, QuestHelper_IndexLookup, QuestHelper_IndexLookup[loc.rc])
    print(loc.c, loc.rc, loc.rz, QuestHelper_IndexLookup, QuestHelper_IndexLookup[loc.rc], QuestHelper_IndexLookup[loc.rc][loc.rz])
  end
  loc.p = QuestHelper_IndexLookup[loc.rc][loc.rz]
  loc.c, loc.rc, loc.rz = nil, nil, nil
  
  return loc
end

local function convert_multiple_loc(locs, locale)
  if not locs then return end
  
  for _, v in ipairs(locs) do
    if v.loc then
      convert_loc(v.loc, locale)
    end
  end
end

--[[
*****************************************************************
Weighted multi-concept accumulation
]]

local function weighted_concept_finalize(data, fraction, minimum, total_needed)
  if #data == 0 then return end

  fraction = fraction or 0.9
  minimum = minimum or 1
  
  table.sort(data, function (a, b) return a.w > b.w end)

  local tw = total_needed
  if not tw then
    tw = 0
    for _, v in pairs(data) do
      tw = tw + v.w
    end
  end
  
  local ept
  local wacu = 0
  for k, v in pairs(data) do
    wacu = wacu + v.w
    v.w = nil
    if wacu >= tw * fraction or (data[k + 1] and data[k + 1].w < minimum) or not data[k + 1] then
      ept = k
      break
    end
  end
  
  if not ept then
    print(total_needed)
    for k, v in pairs(data) do
      print("", v.w)
    end
    assert(false)
  end
  assert(ept, tw)
  
  while #data > ept do table.remove(data) end
  
  return data
end

--[[
*****************************************************************
List-accum functions
]]

local function list_accumulate(item, id, inp)
  if not inp then return end
  
  if not item[id] then item[id] = {} end
  local t = item[id]
  
  if type(inp) == "table" then
    for k, v in pairs(inp) do
      t[v] = (t[v] or 0) + 1
    end
  else
    t[inp] = (t[inp] or 0) + 1
  end
end

local function list_most_common(tbl, mv)
  local mcv = nil
  local mcvw = mv
  for k, v in pairs(tbl) do
    if not mcvw or v > mcvw then mcv, mcvw = k, v end
  end
  return mcv
end

--[[
*****************************************************************
Position accumulation
]]

local function distance(a, b)
  local x = a.x - b.x
  local y = a.y - b.y
  return math.sqrt(x*x+y*y)
end

local function valid_pos(ite)
  if not ite then return end
  if not ite.p or not ite.x or not ite.y then return end
  if QuestHelper_ZoneLookup[ite.p][2] == 0 then return end -- this should get rid of locations showing up in "northrend" or whatever
  return true
end

local function position_accumulate(accu, tpos)
  if not valid_pos(tpos) then return end
  
  assert(tpos.priority)
  
  if not accu[tpos.priority] then accu[tpos.priority] = {} end
  accu = accu[tpos.priority]  -- this is a bit grim
  
  if not accu[tpos.p] then
    accu[tpos.p] = {}
  end
  
  local conti = accu[tpos.p]
  local closest = nil
  local clodist = 300
  for k, v in ipairs(conti) do
    local cdist = distance(tpos, v)
    if cdist < clodist then
      clodist = cdist
      closest = v
    end
  end
  
  if closest then
    closest.x = (closest.x * closest.w + tpos.x) / (closest.w + 1)
    closest.y = (closest.y * closest.w + tpos.y) / (closest.w + 1)
    closest.w = closest.w + 1
  else
    closest = {x = tpos.x, y = tpos.y, w = 1}
    table.insert(conti, closest)
  end
  
  accu.weight = (accu.weight or 0) + 1
end

local function position_has(accu)
  for c, v in pairs(accu) do
    return true -- ha ha
  end
  return false
end

local function position_finalize(sacu, mostest)
  if not position_has(sacu) then return end
  
  --[[local hi = sacu[1] and sacu[1].weight or 0
  local lo = sacu[2] and sacu[2].weight or 0]]
  
  local highest = 0
  for k, v in pairs(sacu) do
    if mostest and k > mostest then continue end
    highest = math.max(highest, k)
  end
  assert(highest > 0 or mostest)
  if highest == 0 then return end
  
  local accu = sacu[highest]  -- highest priority! :D
  
  local pozes = {}
  local tw = 0
  for p, pi in pairs(accu) do
    if type(p) == "string" then continue end
    for _, v in ipairs(pi) do
      table.insert(pozes, {p = p, x = math.floor(v.x + 0.5), y = math.floor(v.y + 0.5), w = v.w})
    end
  end
  
  if #pozes == 0 then return position_finalize(sacu, highest - 1) end
  
  return weighted_concept_finalize(pozes, 0.8, 10)
end

--[[
*****************************************************************
Locale name accum functions
]]

local function name_accumulate(accum, name, locale)
  if not name then return end
  if not accum[locale] then accum[locale] = {} end
  accum[locale][name] = (accum[locale][name] or 0) + 1
end

local function name_resolve(accum)
  local rv = {}
  for k, v in pairs(accum) do
    rv[k] = list_most_common(v)
  end
  return rv
end

--[[
*****************************************************************
Loot accumulation functions
]]

local srces = {
 eng = {},
 mine = {},
 herb = {},
 skin = {},
 open = {},
 extract = {},
 de = {},
 prospect = {},
 mill = {},
 
 loot = {ignoreyesno = true},
 loot_trivial = {ignoreyesno = true, become = "loot"},
 
 rob = {ignoreyesno = true},
 fish = {ignoreyesno = true},
}

local function loot_accumulate(source, sourcetok, Output)
  for typ, specs in pairs(srces) do
    if not specs.ignoreyesno then
      local yes = source[typ .. "_yes"] or 0
      local no = source[typ .. "_no"] or 0
      
      if yes + no < 10 then continue end -- DENY
      
      if yes / (yes + no) < 0.95 then continue end -- DOUBLEDENY
    end
    
    -- We don't actually care about frequency at the moment, just where people tend to get it from. This works in most cases.
    if source[typ .. "_loot"] then for k, c in pairs(source[typ .. "_loot"]) do
      if k ~= "gold" then
        Output(tostring(k), nil, {source = sourcetok, count = c, type = specs.become or typ}, "loot")
      end
    end end
  end
  
  for k, _ in pairs(source) do
    if type(k) ~= "string" then continue end
    local tag = k:match("([^_]+)_items")
    assert(not tag or srces[tag])
  end
end

--[[
*****************************************************************
Standard data accumulation functions
]]

local function standard_pos_accum(accum, value, lv, locale, fluff)
  if not fluff then fluff = 0 end
  for _, v in ipairs(value) do
    if math.mod(#v, 11 + fluff) ~= 0 then
      return true
    end
  end
  
  for _, v in ipairs(value) do
    for off = 1, #v, 11 + fluff do
      local tite = convert_loc(slice_loc(v:sub(off, off + 10), lv), locale)
      if tite then position_accumulate(accum.loc, tite) end
    end
  end
end

local function standard_name_accum(accum, value)
  for k, v in pairs(value) do
    if type(k) == "string" then
      local q = string.match(k, "name_(.*)")
      if q then name_accumulate(accum, q, value.locale) end
    end
  end
end

--[[
*****************************************************************
Chain head
]]

local chainhead = ChainBlock_Create("parse", nil,
  function () return {
    Data = function (self, key, subkey, value, Output)
      local gzx = gzio.open(key, "r")
      local gzd = gzx:read("*a")
      gzx:close()
      gzx = nil
      local dat = pluto.unpersist({}, gzd)
      gzd = nil
      assert(dat)
      
      if do_errors and dat.errors then
        for k, v in pairs(dat.errors) do
          if k ~= "version" then
            for _, d in pairs(v) do
              d.key = k
              d.fileid = value.fileid
              Output(d.local_version, nil, d, "error")
            end
          end
        end
      end
      
      local qhv, wowv, locale, faction = string.match(dat.signature, "([0-9.]+) on ([0-9.]+)/([a-zA-Z]+)/([12])")
      local v = dat.data
      if qhv and wowv and locale and faction
        --and not sortversion("0.80", qhv) -- hacky hacky
      then
        --[[if v.compressed then
          local deco = "return " .. LZW.Decompress(v.compressed, 256, 8)
          print(#v.compressed, #deco)
          local tx = loadstring(deco)()
          assert(tx)
          v.compressed = nil
          for tk, tv in pairs(tx) do
            v[tk] = tv
          end
        end]]
        assert(not v.compressed)
        
        -- quests!
        if do_compile and do_questtables and v.quest then for qid, qdat in pairs(v.quest) do
          qdat.fileid = value.fileid
          qdat.locale = locale
          Output(string.format("%d", qid), qhv, qdat, "quest")
        end end
        
        -- items!
        if do_compile and do_questtables and v.item then for iid, idat in pairs(v.item) do
          idat.fileid = value.fileid
          idat.locale = locale
          Output(tostring(iid), qhv, idat, "item")
        end end
        
        -- monsters!
        if do_compile and do_questtables and v.monster then for mid, mdat in pairs(v.monster) do
          mdat.fileid = value.fileid
          mdat.locale = locale
          Output(tostring(mid), qhv, mdat, "monster")
        end end
        
        -- objects!
        --[[if do_compile and do_questtables and v.object then for oid, odat in pairs(v.object) do
          odat.fileid = value.fileid
          Output(string.format("%s@@%s", oid, locale), qhv, odat, "object")
        end end]]
        
        -- flight masters!
        if do_compile and do_flight and v.flight_master then for fmname, fmdat in pairs(v.flight_master) do
          if type(fmdat.master) == "string" then continue end  -- I don't even know how this is possible
          Output(string.format("%s@@%s@@%s", faction, fmname, locale), qhv, {dat = fmdat, wowv = wowv}, "flight_master")
        end end
        
        -- flight times!
        if do_compile and do_flight and v.flight_times then for ftname, ftdat in pairs(v.flight_times) do
          Output(string.format("%s@@%s@@%s", ftname, faction, locale), qhv, ftdat, "flight_times")
        end end
        
        -- zones!
        if locale == "enUS" and do_zone_map and v.zone then for zname, zdat in pairs(v.zone) do
          local items = {}
          local lv = loc_version(qhv)
          
          for _, key in pairs({"border", "update"}) do
            if items and zdat[key] then for idx, chunk in pairs(zdat[key]) do
              if math.mod(#chunk, 11) ~= 0 then items = nil end
              if not items then break end -- abort, abort
              
              assert(math.mod(#chunk, 11) == 0, tostring(#chunk))
              for point = 1, #chunk, 11 do
                local pos = convert_loc(slice_loc(string.sub(chunk, point, point + 10), lv), locale)
                if pos then
                  if not zonecolors[zname] then
                    local r, g, b = math.ceil(math.random(32, 255)), math.ceil(math.random(32, 255)), math.ceil(math.random(32, 255))
                    zonecolors[zname] = r * 65536 + g * 256 + b
                  end
                  pos.zonecolor = zonecolors[zname]
                  if pos.p and pos.x and pos.y then  -- These might be invalid if there are nils embedded in the string. They might still be useful with only one or two nils, but I've got a bunch of data and don't really need more.
                    if not valid_pos(pos) then
                      items = nil
                      break
                    end
                    
                    pos.c = QuestHelper_ZoneLookup[ite.p][1]
                    table.insert(items, pos)
                  end
                end
              end
            end end
          end
          
          if items then for _, v in pairs(items) do
            v.fileid = value.fileid
            Output(string.format("%d@%04d@%04d", v.c, math.floor(v.y / zone_image_chunksize), math.floor(v.x / zone_image_chunksize)), nil, v, "zone") -- This is inverted - it's continent, y, x, for proper sorting.
            Output(string.format("%d", v.c), nil, {fileid = value.fileid; math.floor(v.x / zone_image_chunksize), math.floor(v.y / zone_image_chunksize)}, "zone_bounds")
          end end
        end end
      else
        --print("Dumped, locale " .. dat.signature)
      end
    end
  } end
)

--[[
*****************************************************************
Object collation
]]

local object_slurp

if false and do_compile then 
  local object_locate = ChainBlock_Create("object_locate", {chainhead},
    function (key) return {
      accum = {name = {}, loc = {}},
      
      fids = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        local name, locale = key:match("(.*)@@(.*)")
        
        if standard_pos_accum(self.accum, value, loc_version(subkey), locale) then return end
        
        while #value > 0 do table.remove(value) end
        
        table.insert(self.accum, value)
        self.fids[value.fileid] = true
      end,
      
      Finish = function(self, Output, Broadcast)
        local fidc = 0
        for k, v in pairs(self.fids) do
          fidc = fidc + 1
        end
        
        if fidc < 3 then return end -- bzzzzzt
        
        local name, locale = key:match("(.*)@@(.*)")
        
        local qout = {}
        
        if position_has(self.accum.loc) then
          qout.loc = position_finalize(self.accum.loc)
        else
          return  -- BZZZZZT
        end
        
        if locale == "enUS" then
          Broadcast("object", {name = name, loc = qout.loc})
          Output("", nil, {type = "data", name = key, data = self.accum}, "reparse")
        else
          Output(key, nil, qout.loc, "link")
          Output("", nil, {type = "data", name = key, data = self.accum}, "reparse")
        end
      end,
    } end,
    sortversion, "object"
  )
  
  local function find_closest(loc, locblock)
    local closest = 5000000000  -- yeah, that's five billion. five fuckin' billion.
    --print(#locblock)
    for _, ite in ipairs(locblock) do
      if loc.p == ite.p then
        local tx = loc.x - ite.x
        local ty = loc.y - ite.y
        local d = tx * tx + ty * ty
        if d < closest then
          closest = d
        end
      end
    end
    return closest
  end
  
  local object_link = ChainBlock_Create("object_link", {object_locate},
    function (key) return {
      
      compare = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        assert(not self.key)
        assert(not self.loc)
        assert(key)
        assert(value)
        
        self.key = key
        self.loc = value
      end,
      
      Receive = function(self, id, data)
        assert(id == "object")
        assert(data)
        assert(not self.compare[data.name])
        
        self.compare[data.name] = data.loc
      end,
      
      Finish = function(self, Output, Broadcast)
        assert(self.key)
        assert(self.loc)
        assert(self.compare)
        
        local results = {}
        local res_size = 0
        
        for enuname, loca in pairs(self.compare) do
          local yaku = 0
          for _, cl in ipairs(loca) do
            yaku = yaku + find_closest(cl, self.loc)
          end
          for _, cl in ipairs(self.loc) do
            yaku = yaku + find_closest(cl, loca)
          end
          yaku = yaku / (#loca + #self.loc)
          assert(not results[enuname])
          results[enuname] = yaku
          res_size = res_size + 1
        end
        
        local nres_size = 0
        local nres = {}
        for k, v in pairs(results) do
          if v < 1000000 then
            nres[k] = v
            nres_size = nres_size + 1
          end
        end
        
        print(res_size, nres_size)
        Output("", nil, {key = key, data = nres}, "combine")
      end,
    } end,
    nil, "link"
  )
  
  local function heap_left(x) return (2*x) end
  local function heap_right(x) return (2*x + 1) end
  
  local function heap_sane(heap)
    local dmp = ""
    local finishbefore = 2
    for i = 1, #heap do
      if i == finishbefore then
        print(dmp)
        dmp = ""
        finishbefore = finishbefore * 2
      end
      dmp = dmp .. string.format("%f ", heap[i].c)
    end
    print(dmp)
    print("")
    for i = 1, #heap do
      assert(not heap[heap_left(i)] or heap[i].c <= heap[heap_left(i)].c)
      assert(not heap[heap_right(i)] or heap[i].c <= heap[heap_right(i)].c)
    end
  end
  
  local function heap_insert(heap, item)
    assert(item)
    table.insert(heap, item)
    local pt = #heap
    while pt > 1 do
      local ptd2 = math.floor(pt / 2)
      if heap[ptd2].c <= heap[pt].c then
        break
      end
      local tmp = heap[pt]
      heap[pt] = heap[ptd2]
      heap[ptd2] = tmp
      pt = ptd2
    end
    --heap_sane(heap)
  end
  

  local function heap_extract(heap)
    local rv = heap[1]
    if #heap == 1 then table.remove(heap) return rv end
    heap[1] = table.remove(heap)
    local idx = 1
    while idx < #heap do
      local minix = idx
      if heap[heap_left(idx)] and heap[heap_left(idx)].c < heap[minix].c then minix = heap_left(idx) end
      if heap[heap_right(idx)] and heap[heap_right(idx)].c < heap[minix].c then minix = heap_right(idx) end
      if minix ~= idx then
        local tx = heap[minix]
        heap[minix] = heap[idx]
        heap[idx] = tx
        idx = minix
      else
        break
      end
    end
    --heap_sane(heap)
    return rv
  end
  
  --[[
  do
    local heaptest = {}
    for k = 1, 10 do
      heap_insert(heaptest, {c = math.random()})
    end
    while #heaptest > 0 do
      heap_extract(heaptest)
    end
  end]]
  
  local object_combine = ChainBlock_Create("object_combine", {object_link},
    function (key) return {
    
      source = {enUS = {}},
      heap = {},
    
      Data = function(self, key, subkey, value, Output)
        local name, locale = value.key:match("(.*)@@(.*)")  -- boobies regexp
        -- insert shit into a heap
        if not self.source[locale] then self.source[locale] = {} end
        self.source[locale][name] = {}
        for k, v in pairs(value.data) do
          self.source.enUS[k] = {linkedto = {}}
          heap_insert(self.heap, {c = v, dst_locale = locale, dst = name, src = k})
        end
      end,
      
      Receive = function() end,
      
      Finish = function(self, Output, Broadcast)
        print("heap is", #self.heap)
        
        local llst = 0
        while #self.heap > 0 do
          local ite = heap_extract(self.heap)
          assert(ite.c >= llst)
          llst = ite.c
          
          if not self.source.enUS[ite.src].linkedto[ite.dst_locale] and not self.source[ite.dst_locale][ite.dst].linked then
            self.source.enUS[ite.src].linkedto[ite.dst_locale] = ite.dst
            self.source[ite.dst_locale][ite.dst].linked = true
            print(string.format("Linked %s to %s/%s (%f)", ite.src, ite.dst_locale, ite.dst, ite.c))
          end
        end
        -- pull shit out of the heap, link things up
        
        -- determine unique IDs for everything we have left
        
        -- output stuff for actual parsing and processing of any remaining data
        -- also, output a chart of what we linked
        -- remember to output that chart in order-of-linkage
      end,
    } end,
    nil, "combine"
  )
  
  
  -- then, now that we finally have IDs, we do our standard mambo of stuff
  
  
  --[[object_slurp = ChainBlock_Create("object_slurp", {chainhead},
    function (key) return {
      accum = {name = {}, loc = {}},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        if standard_pos_accum(self.accum, value, loc_version(subkey)) then return end
        name_accumulate(self.accum.name, key, value.locale)
        
        while #value > 0 do table.remove(value) end
        value.locale = nil
        
        table.insert(accum, value)
      end,
      
      Finish = function(self, Output)
        self.accum.name = name_resolve(self.accum.name)
        
        local qout = {}
        
        if dbg_data then qout.name = self.accum.name end
        if position_has(self.accum.loc) then qout.loc = position_finalize(self.accum.loc) end
        
        local has_stuff = false
        for k, v in pairs(qout) do
          has_stuff = true
          break
        end
        if has_stuff then
          Output("", nil, {id="object", key=key, data=qout}, "output")
        end
      end,
    } end,
    sortversion, "object"
  )]]
end

--[[
*****************************************************************
Monster collation
]]

local monster_slurp

if do_compile and do_questtables then 
  monster_slurp = ChainBlock_Create("monster_slurp", {chainhead},
    function (key) return {
      accum = {name = {}, loc = {}},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        if standard_pos_accum(self.accum, value, loc_version(subkey), value.locale, 2) then return end
        if standard_name_accum(self.accum.name, value) then return end
        
        loot_accumulate(value, {type = "monster", id = tonumber(key)}, Output)
      end,
      
      Finish = function(self, Output)
        self.accum.name = name_resolve(self.accum.name)
        
        local qout = {}
        
        if dbg_data then qout.dbg_name = self.accum.name.enUS end
        if position_has(self.accum.loc) then qout.loc = position_finalize(self.accum.loc) end
        
        local has_stuff = false
        for k, v in pairs(qout) do
          has_stuff = true
          break
        end
        assert(tonumber(key))
        if has_stuff then
          Output("*/*", nil, {id="monster", key=tonumber(key), data=qout}, "output")
        end
        for k, v in pairs(self.accum.name) do
          Output(("%s/*"):format(k), nil, {id="monster", key=tonumber(key), data={name=v}}, "output")
        end
      end,
    } end,
    sortversion, "monster"
  )
end

--[[
local monster_pack
if do_compile then 
  monster_pack = ChainBlock_Create("monster_pack", {monster_slurp},
    function (key) return {
      data = {},
      
      Data = function(self, key, subkey, value, Output)
        assert(not self.data[value.key])
        if not self.data[value.key] then self.data[value.key] = {} end
        self.data[value.key] = value.data
      end,
      
      Finish = function(self, Output, Broadcast)
        Broadcast(nil, {monster=self.data})
      end,
    } end
  )
end]]

--[[
*****************************************************************
Item collation
]]

local item_name_package
local item_slurp
local item_parse

if do_compile and do_questtables then
  item_parse = ChainBlock_Create("item_parse", {chainhead},
    function (key) return {
      accum = {name = {}},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        name_accumulate(self.accum.name, value.name, value.locale)
        
        loot_accumulate(value, {type = "item", id = tonumber(key)}, Output)
      end,
      
      Finish = function(self, Output)
        self.accum.name = name_resolve(self.accum.name)
        
        local qout = {}
        
        -- we don't actually care about the level, so we don't bother to store it. Really, we only care about the name for debug purposes also, so we should probably get rid of it before release.
        if dbg_data then qout.dbg_name = self.accum.name.enUS end
        
        --[[Output("", nil, {key = key, name = qout.name}, "name")]]
        
        local has_stuff = false
        for k, v in pairs(qout) do
          has_stuff = true
          break
        end
        
        if has_stuff then
          Output(key, nil, {type = "core", data = qout}, "item")
        end
        for k, v in pairs(self.accum.name) do
          Output(("%s/*"):format(k), nil, {id="item", key=tonumber(key), data={name=v}}, "output")
        end
      end,
    } end,
    sortversion, "item"
  )
  
  --[[
  item_name_package = ChainBlock_Create("item_name_package", {item_slurp_first},
    function (key) return {
      accum = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        assert(not self.accum[value.key])
        self.accum[value.key] = value.name
      end,
      
      Finish = function(self, Output, Broadcast)
        Broadcast("item_name_package", self.accum)
      end,
    } end,
    nil, "name"
  )]]
  
  -- Input to this module is kind of byzantine, so I'm documenting it here.
  -- {Key, Subkey, Value}
  
  -- {999, nil, {source = {type = "monster", id = 12345}, count = 104, type = "skin"}}
  -- Means: "We've seen 104 skinnings of item #999 from monster #12345"
  local lootables = {}
  if monster_slurp then table.insert(lootables, monster_slurp) end
  if item_parse then table.insert(lootables, item_parse) end
  
  local loot_merge = ChainBlock_Create("loot_merge", lootables,
    function (key) return {
      lookup = setmetatable({__exists__ = {}}, 
        {__index = function(self, key)
          if not rawget(self, key.sourcetype) then self[key.sourcetype] = {} end
          if not self[key.sourcetype][key.sourceid] then self[key.sourcetype][key.sourceid] = {} end
          if not self[key.sourcetype][key.sourceid][key.type] then self[key.sourcetype][key.sourceid][key.type] = key  table.insert(self.__exists__, key) end
          return self[key.sourcetype][key.sourceid][key.type]
        end
        }),
      
      dtime = 0,
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        --local st = os.time()
        local vx = self.lookup[{sourcetype = value.source.type, sourceid = value.source.id, type = value.type}]
        vx.w = (vx.w or 0) + value.count
        --self.dtime = self.dtime + os.time() - st
      end,
      
      Finish = function(self, Output)
        --local st = os.time()
        local tacu = {}
        for k, v in pairs(self.lookup.__exists__) do
          table.insert(tacu, v)
        end
        
        --local tacuc = #tacu
        
        Output(key, nil, {type = "loot", data = weighted_concept_finalize(tacu, 0.9, 10)}, "item")
      end,
    } end,
    nil, "loot"
  )
  
  item_slurp = ChainBlock_Create("item_slurp", {item_parse, loot_merge},
    function (key) return {
      accum = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        assert(not self.accum[value.type])
        self.accum[value.type] = value.data
      end,
      
      Finish = function(self, Output)
        local qout = self.accum.core
        if not qout then qout = {} end -- Surprisingly, we don't care much about the "core".
        
        if self.accum.loot then for k, v in pairs(self.accum.loot) do
          qout[k] = v
        end end
        
        if key ~= "gold" then -- okay technically the whole thing could have been ignored, but
          assert(tonumber(key))
          Output("*/*", nil, {id="item", key=tonumber(key), data=qout}, "output")
        end
      end,
    } end,
    nil, "item"
  )
end

--[[
*****************************************************************
Quest collation
]]

local quest_slurp

if do_compile and do_questtables then
  local function find_important(dat, count)
    local mungedat = {}
    local tweight = 0
    for k, v in pairs(dat) do
      table.insert(mungedat, {d = k, w = v})
      tweight = tweight + v
    end
    
    if tweight < count / 2 then return end  -- we just don't have enough, something's gone wrong
    
    return weighted_concept_finalize(mungedat, 0.9, 10, count) -- this is not ideal, but it's functional
  end

  quest_slurp = ChainBlock_Create("quest_slurp", {chainhead --[[, item_name_package]]},
    function (key) return {
      accum = {name = {}, criteria = {}, level = {}, start = {}, finish = {}},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        local lv = loc_version(subkey)
        
        -- Split apart the start/end info. This includes locations and possibly the monster that was targeted.
        if value.start then
          value.start = split_quest_startend(value.start, lv)
          convert_multiple_loc(value.start, value.locale)
        end
        if value["end"] then   --sigh
          value.finish = split_quest_startend(value["end"], lv)
          convert_multiple_loc(value.finish, value.locale)
          value["end"] = nil
        end
        
        -- Parse apart the old complicated criteria strings
        if not value.criteria then value.criteria = {} end
        for k, v in pairs(value) do
          local item, token = string.match(k, "criteria_([%d]+)_([a-z]+)")
          if token then
            assert(item)
            
            if token == "satisfied" then
              value[k] = split_quest_satisfied(value[k], lv)
              convert_multiple_loc(value[k], value.locale)
            end
            
            if not value.criteria[tonumber(item)] then value.criteria[tonumber(item)] = {} end
            value.criteria[tonumber(item)][token] = value[k]
            value[k] = nil
          end
        end
        
        -- Accumulate the old criteria strings into our new data
        if value.start then for k, v in pairs(value.start) do position_accumulate(self.accum.start, v.loc) end end
        if value.finish then for k, v in pairs(value.finish) do position_accumulate(self.accum.finish, v.loc) end end
        
        self.accum.appearances = (self.accum.appearances or 0) + 1
        for id, dat in pairs(value.criteria) do
          if not self.accum.criteria[id] then self.accum.criteria[id] = {count = 0, loc = {}, monster = {}, item = {}} end
          local cid = self.accum.criteria[id]
          
          if dat.satisfied then
            for k, v in pairs(dat.satisfied) do
              position_accumulate(cid.loc, v.loc)
              cid.count = cid.count + (v.c or 1)
              list_accumulate(cid, "monster", v.monster)
              list_accumulate(cid, "item", v.item)
            end
          end
          
          cid.appearances = (cid.appearances or 0) + 1
          
          list_accumulate(cid, "type", dat.type)
        end
        
        -- Accumulate names and levels
        if value.name then
          -- Names is a little complicated - we want to get rid of any recommended-level tags that we might have.
          local vnx = string.match(value.name, "%b[]%s*(.*)")
          if not vnx then vnx = value.name end
          
          name_accumulate(self.accum.name, vnx, value.locale)
        end
        list_accumulate(self.accum, "level", value.level)
      end,
      
      --[[
      Receive = function(self, id, data)
        self.namedb = data
      end,]]
      
      Finish = function(self, Output)
        self.accum.name = name_resolve(self.accum.name)
        self.accum.level = list_most_common(self.accum.level)
        
        -- First we see if we need to chop out some criteria
        do
          local appearances = self.accum.appearances * 0.9
          appearances = appearances * 0.9
          local strips = {}
          for k, v in pairs(self.accum.criteria) do
            if v.appearances < appearances then
              table.insert(strips, k)
            end
          end
          for _, v in pairs(strips) do
            self.accum.criteria[v] = nil
          end
        end
        
        local qout = {}
        for k, v in pairs(self.accum.criteria) do
          
          v.type = list_most_common(v.type)
          
          if not qout.criteria then qout.criteria = {} end
          
          -- temp debug output
          -- We shouldn't actually be doing this, we should be figuring out which monsters and items this really correlates to.
          -- We're currently not. However, this will require correlating with the names for monsters and items.
          local snaggy, typ
          if v.type == "monster" then
            snaggy = find_important(v.monster, v.count)
            typ = "kill"
          elseif v.type == "item" then
            snaggy = find_important(v.item, v.count)
            typ = "get"
          end
          
          qout.criteria[k] = {}
          
          if dbg_data then
            qout.criteria[k].item = v.item
            qout.criteria[k].monster = v.monster
            qout.criteria[k].count = v.count
            qout.criteria[k].type = v.type
            qout.criteria[k].appearances = v.appearances
            
            qout.criteria[k].snaggy = snaggy or "(nothin')"
          end
          
          if snaggy then
            assert(#snaggy > 0)
            
            for _, x in ipairs(snaggy) do
              table.insert(qout.criteria[k], {sourcetype = v.type, sourceid = x.d, type = typ})
            end
          end
          
          if position_has(v) then qout.criteria[k].loc = position_finalize(v.loc) end
        end
        
        --if position_has(self.accum.start) then qout.start = { loc = position_finalize(self.accum.start) } end  -- we don't actually care about the start position
        if position_has(self.accum.finish) then qout.finish = { loc = position_finalize(self.accum.finish) } end
        
        -- we don't actually care about the level, so we don't bother to store it. Really, we only care about the name for debug purposes also, so we should probably get rid of it before release.
        if dbg_data then
          qout.dbg_name = self.accum.name.enUS
          qout.appearances = self.accum.appearances or "none"
        end
        
        local has_stuff = false
        for k, v in pairs(qout) do
          has_stuff = true
          break
        end
        assert(tonumber(key))
        if has_stuff then
          --print("Quest output " .. tostring(key))
          Output("*/*", nil, {id="quest", key=tonumber(key), data=qout}, "output")
        end
        for k, v in pairs(self.accum.name) do
          Output(("%s/*"):format(k), nil, {id="quest", key=tonumber(key), data={name=v}}, "output")
        end
      end,
    } end,
    sortversion, "quest"
  )
end

--[[
*****************************************************************
Zone collation
]]

if do_zone_map then
  local zone_draw = ChainBlock_Create("zone_draw", {chainhead},
    function (key) return {
      imagepiece = Image(zone_image_outchunk, zone_image_outchunk),
      ct = 0,
      
      Data = function(self, key, subkey, value, Output)
        self.imagepiece:set(math.floor(math.umod(value.x, zone_image_chunksize) / zone_image_descale), math.floor(math.umod(value.y, zone_image_chunksize) / zone_image_descale), value.zonecolor)
        self.ct = self.ct + 1
      end,
      
      Finish = function(self, Output)
        if self.ct > 0 then Output(string.gsub(key, "@.*", ""), key, self.imagepiece, "zone_stitch") end
      end,
    } end,
    nil, "zone"
  )
  
  local zone_bounds = ChainBlock_Create("zone_bounds", {chainhead},
    function (key) return {
      sx = 1000000,
      sy = 1000000,
      ex = -1000000,
      ey = -1000000,
      
      ct = 0,
      
      Data = function(self, key, subkey, value, Output)
        self.sx = math.min(self.sx, value[1])
        self.sy = math.min(self.sy, value[2])
        self.ex = math.max(self.ex, value[1])
        self.ey = math.max(self.ey, value[2])
        self.ct = self.ct + 1
      end,
      
      Finish = function(self, Output)
        if self.ct > 1000 then
          Output(key, nil, {sx = self.sx, sy = self.sy, ex = self.ex, ey = self.ey}, "zone_stitch")
        end
      end,
    } end,
    nil, "zone_bounds"
  )
  
  local zone_stitch = ChainBlock_Create("zone_stitch", {zone_draw, zone_bounds},
    function (key) return {
      Data = function(self, key, subkey, value, Output)
        if not subkey then
          self.bounds = value
          self.imagewriter = ImageTileWriter(string.format("intermed/zone_%s.png", key), self.bounds.ex - self.bounds.sx + 1, self.bounds.ey - self.bounds.sy + 1, zone_image_outchunk)
          return
        end
        
        if not self.bounds then return end
        
        local yp, xp = string.match(subkey, "[%d-]+@([%d-]+)@([%d-]+)")
        if not xp or not yp then print(subkey) end
        xp = xp - self.bounds.sx
        yp = yp - self.bounds.sy

        self.imagewriter:write_tile(xp, yp, value)
      end,
      
      Finish = function(self, Output)
        if self.imagewriter then self.imagewriter:finish() end
      end,
    } end,
    nil, "zone_stitch"
  )
end

--[[
*****************************************************************
Flight paths
]]

--[[

let us talk about flight paths

sit down

have some tea

very well, let us begin

So, flight masters. First, accumulate each one of each faction/name/locale set. This includes both monsterid (pick most common) and vertex location (simple most-common.)

Then we link together name/locale's of various factions, just so we can get names out and IDs.

After that, we take our routes and determine IDs, with name-lookup for the first and last node, and vertex-lookup for all other nodes, with some really low error threshold. Pick the mean time for each route that has over N tests, then dump those.

For now we'll assume that this will provide sufficiently accurate information.

We'll do this, then start working on the clientside code.

]]

local flight_data_output
local flight_table_output
local flight_master_name_output

if do_compile and do_flight then
  local flight_master_parse = ChainBlock_Create("flight_master_parse", {chainhead},
    function (key) return {
      mids = {},
      locs = {},
      newest_version = nil,
      count = 0,
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        if not sortversion(self.newest_version, value.wowv) then
          self.newest_version = value.wowv
        end
        
        list_accumulate(self, "mids", value.dat.master)
        list_accumulate(self, "locs", string.format("%s@@%s", value.dat.x, value.dat.y))
        self.count = self.count + 1
      end,
      
      Finish = function(self, Output)
        if self.count < 10 then return end
        
        local faction, name, locale = key:match("(.*)@@(.*)@@(.*)")
        assert(faction)
        assert(name)
        assert(locale)
        local mid = list_most_common(self.mids)
        local loc = list_most_common(self.locs)
        
        Output(string.format("%s@@%s", loc, faction), nil, {locale = locale, name = name, mid = mid, version = self.newest_version})
      end,
    } end,
    sortversion, "flight_master"
  )
  
  local flight_master_accumulate = ChainBlock_Create("flight_master_accumulate", {flight_master_parse},
    function (key) return {
      
      names = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        if self.names[value.locale] then
          print(key, value.locale, self.names[value.locale], value.name)
          
          print(self.names[value.locale].version, value.version, sortversion(self.names[value.locale].version, value.version), self.names[value.locale].name, value.name)
          assert(self.names[value.locale].version ~= value.version)
          print(self.names[value.locale].version, value.version, sortversion(self.names[value.locale].version, value.version))
          
          if not sortversion(self.names[value.locale].version, value.version) then
            self.names[value.locale] = nil  -- we just blow it away and rebuild it later
          else
            return
          end
        end
        assert(not self.names[value.locale])
        assert(not self.mid or not value.mid or self.mid == value.mid, key)
        
        self.names[value.locale] = {name = value.name, version = value.version}
        self.mid = value.mid
      end,
      
      Finish = function(self, Output)
        local x, y, faction = key:match("(.*)@@(.*)@@(.*)")
        local namepack = {}
        for k, v in pairs(self.names) do
          namepack[k] = v.name
        end
        
        Output(tostring(faction), nil, {x = x, y = y, faction = faction, mid = self.mid, names = namepack})
      end,
    } end
  )
  
  if false then
    local flight_master_test = ChainBlock_Create("flight_master_test", {flight_master_accumulate},
      function (key) return {
        
        data = {},
        
        -- Here's our actual data
        Data = function(self, key, subkey, value, Output)
          table.insert(self.data, value)
        end,
        
        Finish = function(self, Output)
          local links = {}
          for x = 1, #self.data do
            for y = x + 1, #self.data do
              local dx = self.data[x].x - self.data[y].x
              local dy = self.data[x].y - self.data[y].y
              local diff = math.sqrt(dx * dx + dy * dy)
              if diff < 0.001 then
                print("------")
                print(diff)
                dbgout(self.data[x])
                dbgout(self.data[y])
              end
              table.insert(links, diff)
            end
          end
          
          table.sort(links)
          
          for x = 1, math.min(100, #links) do
            print(links[x])
          end
        end,
      } end
    )
  end
  
  local flight_master_pack = ChainBlock_Create("flight_master_pack", {flight_master_accumulate},
    function (key) return {
      pack = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        table.insert(self.pack, value)
      end,
      
      Finish = function(self, Output, Broadcast)
        print("Broadcasting", key)
        Broadcast(key, self.pack)
        
        Output(key, nil, "", "name_output") -- just exists to make sure name_output does something
      end,
    } end
  )
  
  local function findname(lookup, dat, locale)
    for k, v in ipairs(lookup) do
      if v.names[locale] == dat then return k end
    end
  end
  
  local flight_master_times = ChainBlock_Create("flight_master_times", {flight_master_pack, chainhead},
    function (key) local src, dst, faction, locale = key:match("(.*)@@(.*)@@(.*)@@(.*)") assert(faction and src and dst and locale) return {
      
      Data = function(self, key, subkey, value, Output)
        if self.fail then return end
        
        if not self.table then if not e or e > 1000 then print("Entire missing faction table!") end return end
        assert(self.table)
        
        if not self.src or not self.dst then
          self.src = findname(self.table, src, locale)
          self.dst = findname(self.table, dst, locale)
          
          --if not self.src then print("failed to find ", src) end
          --if not self.dst then print("failed to find ", dst) end
          if not self.src or not self.dst then self.fail = true return end
        end
        
        assert(self.src)
        assert(self.dst)
        
        for k, v in pairs(value) do
          if type(v) == "number" and value[k .. "##count"] then
            local path = {}
            for node in k:gmatch("[^@]+") do
              local x, y = node:match("(.*):(.*)")
              x, y = tonumber(x), tonumber(y)
              local closest, closestval = nil, 0.01
              for k, v in ipairs(self.table) do
                local dx, dy = v.x - x, v.y - y
                dx, dy = dx * dx, dy * dy
                local dist = math.sqrt(dx + dy)
                if dist < closestval then
                  closestval = dist
                  closest = k
                end
              end
              
              if not closest then print("Can't find nearby flightpath") return end
              assert(closest)
              table.insert(path, closest)
            end
            table.insert(path, self.dst)
            
            local tx = tostring(self.src)
            for _, v in ipairs(path) do
              tx = tx .. "@" .. tostring(v)
            end
            
            Output(faction .. "/" .. tx, nil, v / value[k .. "##count"])
          end
        end
      end,
      
      Receive = function(self, id, value)
        if id == faction then self.table = value end
      end,
    } end,
    nil, "flight_times"
  )
  
  local flight_master_assemble = ChainBlock_Create("flight_master_assemble", {flight_master_times},
    function (key) return {
      dat = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        table.insert(self.dat, value)
      end,
      
      Finish = function(self, Output, Broadcast)
        table.sort(self.dat)
        
        local chop = math.floor(#self.dat / 3)
        
        local acu = 0
        local ct = 0
        for i = 1 + chop, #self.dat - chop do
          acu = acu + self.dat[i]
          ct = ct + 1
        end
        
        acu = acu / ct
        
        if #self.dat > 10 then
          Output(key:match("([%d]+/[%d]+)@.+"), nil, {path = key, distance = acu})
        end
      end,
    } end
  )
  
  flight_data_output = ChainBlock_Create("flight_data_output", {flight_master_assemble},
    function (key) local faction, src = key:match("([%d]+)/([%d]+)") assert(faction and src) return {
      chunky = {},
      
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
        local f, s, m, e = value.path:match("([%d]+)/([%d]+)@(.+)@([%d]+)")
        if not f then f, s, e = value.path:match("([%d]+)/([%d]+)@([%d]+)") end
        assert(f and s and e)
        assert((f .. "/" .. s) == key)
        s = tonumber(s)
        e = tonumber(e)
        assert(s)
        assert(e)
        
        if not self.chunky[e] then
          self.chunky[e] = {}
        end
        
        local dex = {distance = value.distance, path = {}}
        if m then for x in m:gmatch("[%d]+") do
          assert(tonumber(x))
          table.insert(dex.path, tonumber(x))
        end end
        
        table.insert(self.chunky[e], dex)
      end,
      
      Finish = function(self, Output, Broadcast)
        for _, v in pairs(self.chunky) do
          table.sort(v, function(a, b) return a.distance < b.distance end)
        end
        
        Output(string.format("*/%s", faction), nil, {id = "flightpaths", key = tonumber(src), data = self.chunky}, "output_direct")
      end,
    } end
  )
  
  flight_master_name_output = ChainBlock_Create("flight_master_name_output", {flight_master_pack},
    function (key) return {
      -- Here's our actual data
      Data = function(self, key, subkey, value, Output)
      end,
      
      Receive = function(self, id, value)
        if id == key then self.table = value end
      end,
      
      Finish = function(self, Output, Broadcast)
        print("finnish")
        for k, v in ipairs(self.table) do
          Output(string.format("*/%s", key), nil, {id = "flightmasters", key = k, data = {mid = v.mid}}, "output")
          for l, n in pairs(v.names) do
            Output(string.format("%s/%s", l, key), nil, {id = "flightmasters", key = k, data = {name = n}}, "output_direct")
          end
        end
      end,
    } end,
    nil, "name_output"
  )
end

--[[
*****************************************************************
Final file generation
]]

local sources = {}
if quest_slurp then table.insert(sources, quest_slurp) end
if item_slurp then table.insert(sources, item_slurp) end
if item_parse then table.insert(sources, item_parse) end
if monster_slurp then table.insert(sources, monster_slurp) end
if object_slurp then table.insert(sources, object_slurp) end
if flight_data_output then table.insert(sources, flight_data_output) end
if flight_table_output then table.insert(sources, flight_table_output) end
if flight_master_name_output then table.insert(sources, flight_master_name_output) end

local function do_loc_choice(file, item, toplevel)
  local has_linkloc = false
  local count = 0
  
  do
    local loc_obliterate = {}
    for k, v in ipairs(item) do
      local worked = false
      if file[v.sourcetype] and file[v.sourcetype][v.sourceid] and file[v.sourcetype][v.sourceid]["*/*"] then
        local valid, tcount = do_loc_choice(file, file[v.sourcetype][v.sourceid]["*/*"])
        if valid then
          has_linkloc = true
          worked = true
          count = count + tcount
        end
      end
      
      if not worked then
        table.insert(loc_obliterate, k)
      end
    end
    
    for i = #loc_obliterate, 1, -1 do
      table.remove(item, loc_obliterate[i])
    end
  end
  
  if dbg_data then
    item.full_objective_count = count
  end
  
  local reason = string.format("%s, %s, %s", tostring(has_linkloc), tostring(count), (item.loc and tostring(#item.loc) or "(no item.loc)"))
  
  if has_linkloc then
    assert(count > 0)
    if toplevel and count > 10 and item.loc then
      while #item.loc > 10 do
        table.remove(item.loc)
      end
      count = #item.loc
    elseif toplevel and count > 10 then
      item.loc = {} -- we're doing this just so we can say "hey, we don't want to use the original locations"
      count = 0 -- :(
    else
      if dbg_data then
        item.loc_unused = item.loc_unused or item.loc
      end
      
      item.loc = nil
    end
  else
    assert(count == 0)
    if item.loc then count = #item.loc end
    
    if dbg_data then
      if #item > 0 then
        item.link_unused = {}
        while #item > 0 do table.insert(item.link_unused, table.remove(item, 1)) end
      end
    else
      while #item > 0 do table.remove(item) end
    end
  end
  
  local valid = item.loc or #item > 0
  --[[if valid then -- technically not necessarily true
    assert(count > 0)
  else
    assert(count == 0)
  end]]
  return valid, count, reason
end

local function mark_chains(file, item)
  for k, v in ipairs(item) do
    if file[v.sourcetype][v.sourceid] then
      file[v.sourcetype][v.sourceid].used = true
      if file[v.sourcetype][v.sourceid]["*/*"] then mark_chains(file, file[v.sourcetype][v.sourceid]["*/*"]) end
    end
  end
end

local file_collater = ChainBlock_Create("file_collater", sources,
  function (key) return {
    Data = function(self, key, subkey, value, Output)
      Output("", nil, {fragment = key, value = value})
    end
  } end,
  nil, "output"
)

local file_cull = ChainBlock_Create("file_cull", {file_collater},
  function (key) return {
    finalfile = {},
    
    Data = function(self, key, subkey, value, Output)
      assert(value.value.data)
      assert(value.value.id)
      assert(value.value.key)
      assert(value.fragment)
      
      if not self.finalfile[value.value.id] then self.finalfile[value.value.id] = {} end
      if not self.finalfile[value.value.id][value.value.key] then self.finalfile[value.value.id][value.value.key] = {} end
      assert(not self.finalfile[value.value.id][value.value.key][value.fragment])
      self.finalfile[value.value.id][value.value.key][value.fragment] = value.value.data
    end,
    
    Finish = function(self, Output)
      -- First we go through and check to see who's got actual locations, and cull either location or linkage
      local qct = {}
      if self.finalfile.quest then for k, v in pairs(self.finalfile.quest) do
        if v["*/*"] and v["*/*"].criteria then
          for cid, crit in pairs(v["*/*"].criteria) do
            local _, ct, reason = do_loc_choice(self.finalfile, crit, true)
            table.insert(qct, {ct = ct, id = string.format("%d/%d", k, cid), reason = reason})
          end
        end
      end end
      table.sort(qct, function(a, b) return a.ct < b.ct end)
      for _, v in ipairs(qct) do
        print("qct", v.ct, v.id, v.reason)
      end
      
      -- Then we mark used/unused items
      if self.finalfile.quest then for k, v in pairs(self.finalfile.quest) do
        v.used = true
        if v["*/*"] and v["*/*"].criteria then
          for _, crit in pairs(v["*/*"].criteria) do
            mark_chains(self.finalfile, crit)
          end
        end
      end end
      
      if self.finalfile.flightmasters then for k, v in pairs(self.finalfile.flightmasters) do
        for _, d in pairs(v) do
          if d.mid then
            mark_chains(self.finalfile, {{sourcetype = "monster", sourceid = d.mid}})
          end
        end
        v.used = true
      end end
      
      -- Then we optionally cull and unmark
      for t, d in pairs(self.finalfile) do
        for k, v in pairs(d) do
          if dbg_data then
            for _, tv in pairs(v) do
              if type(tv) == "table" then tv.used = v.used or false end
            end
          end
          
          v.used = nil
        end
        
        if not dbg_data then
          self.finalfile[t] = d
        end
      end
      
      for t, d in pairs(self.finalfile) do
        for k, d2 in pairs(d) do
          for s, d3 in pairs(d2) do
            assert(d3)
            Output(s, nil, {id = t, key = k, data = d3}, "output_direct")
          end
        end
      end
    end
  } end
)

local output_sources = {}
for _, v in ipairs(sources) do
  table.insert(output_sources, v)
end
table.insert(output_sources, file_cull)

local function LZW_precompute_table(inputs, tokens)
  -- shared init code
  local d = {}
  local i
  for i = 1, #tokens do
    d[tokens:sub(i, i)] = 0
  end
  
  for _, input in ipairs(inputs) do
    local w = ""
    for ci = 1, #input do
      local c = input:sub(ci, ci)
      local wcp = w .. c
      if d[wcp] then
        w = wcp
        d[wcp] = d[wcp] + 1
      else
        d[wcp] = 1
        w = c
      end
    end
  end
  
  local freq = {}
  for k, v in pairs(d) do
    if #k > 1 then
      table.insert(freq, {v, k})
    end
  end
  table.sort(freq, function(a, b) return a[1] < b[1] end)
  
  return freq
end

local function pdump(v)
  assert(type(v) == "table")
  local writo = {write = function (self, data) Merger.Add(self, data) end}
  persistence.store(writo, v)
  if not loadstring("return " .. Merger.Finish(writo)) then print(Merger.Finish(writo)) assert(false) end
  assert(loadstring("return " .. Merger.Finish(writo)))
  local dense = Diet(Merger.Finish(writo))
  if not dense then print("Couldn't condense") print(Merger.Finish(writo)) return end  -- wellp
  local dist = dense:match("{(.*)}")
  assert(dist)
  return dist
end


local compress_split = ChainBlock_Create("compress_split", output_sources,
  function (key) return {
    Data = function(self, key, subkey, value, Output)
      Output(key .. "/" .. value.id, subkey, value)
    end,
  } end, nil, "output_direct")
  
local compress = ChainBlock_Create("compress", {compress_split},
  function (key) return {
    finalfile = {},
    
    Data = function(self, key, subkey, value, Output)
      assert(value.data, string.format("%s, %s", tostring(value.id), tostring(value.key)))
      assert(value.id)
      assert(value.key)
      
      assert(not self.finalfile[value.key])
      self.finalfile[value.key] = value.data
    end,
    
    Finish = function(self, Output)
      
      local fname = "static"
      
      local locale, faction, segment = key:match("(.*)/(.*)/(.*)")
      local orig_locale, orig_faction, orig_segment = locale, faction, segment
      assert(locale and faction)
      if locale == "*" then locale = nil end
      if faction == "*" then faction = nil end      
      
      if locale then
        fname = fname .. "_" .. locale
      end
      if faction then
        fname = fname .. "_" .. faction
      end
      
      -- First, compression.
      if do_compress then
        local d = self.finalfile
        local k = segment
        
        local dict = {}
        
        for sk, v in pairs(d) do
          assert(type(sk) ~= "string" or not sk:match("__.*"))
          assert(type(v) == "table")
          
          dist = pdump(v)
          if not dist then continue end
          
          for i = 1, #dist do
            dict[dist:byte(i)] = true
          end
          
          self.finalfile[sk] = dist
        end
        
        local dicto = {}
        for k, v in pairs(dict) do
          table.insert(dicto, k)
        end
        
        table.sort(dicto)
        
        local dictix = string.char(unpack(dicto))
        assert(dictix)
        d.__dictionary = dictix
        
        -- Now we build the precomputed LZW table
        do
          -- hackery steakery
          if locale == nil or locale == "enUS" or true then
            local inps = {}
            for _, v in pairs(d) do
              table.insert(inps, v)
            end
            local preco = LZW_precompute_table(inps, dictix)
            
            local total = 0
            for _, v in ipairs(preco) do
              total = total + v[1] / #v[2]
            end
            
            for _, v in ipairs(preco) do
              if v[1] > total / 100 then
                --print(locale, faction, v[1], v[2])
              end
            end
            
            --local ofile = ("final/%s_%s.stats"):format(fname, k)
            --fil = io.open(ofile, "w")
            
            --for i = 1, 51, 10 do
              --local thresh = total / 100 / i
              local thresh = total / 100 / 40 -- this seems about the right threshold
              
              local tix = {}
              for _, v in ipairs(preco) do
                if v[1] > thresh then
                  table.insert(tix, v[2])
                end
              end
              table.sort(tix, function(a, b) return #a > #b end)
              
              local fundatoks = {}
              local usedtoks = {}
              for _, v in ipairs(tix) do
                if usedtoks[v] then continue end
                
                for i = 1, #v do
                  local sub = v:sub(1, i)
                  usedtoks[sub] = true
                end
                table.insert(fundatoks, v)
              end
              
              if segment ~= "flightmasters" or true then  -- the new decompression is quite a bit slower, and flightmasters are decompressed in large bulk on logon
                local redictix = dictix
                if not redictix:find("\"") then redictix = redictix .. "\"" end
                if not redictix:find(",") then redictix = redictix .. "," end
                if not redictix:find("\\") then redictix = redictix .. "\\" end
                local ftd = pdump(fundatoks)
                self.finalfile.__tokens = LZW.Compress_Dicts(ftd, redictix)
                if LZW.Decompress_Dicts(self.finalfile.__tokens, redictix) ~= ftd then
                  print(ftd)
                  print(LZW.Decompress_Dicts(self.finalfile.__tokens, redictix))
                  print(dictix)
                  print(redictix)
                end
                assert(LZW.Decompress_Dicts(self.finalfile.__tokens, redictix) == ftd)
                
                local prep_id, prep_id_size, prep_is = LZW.Prepare(dictix, fundatoks)
                
                --local dictsize = #self.finalfile.__tokens
                --local datsize = 0
                
                for sk, v in pairs(d) do
                  if (type(sk) ~= "string" or not sk:match("__.*")) and type(v) == "string" then
                    assert(type(v) == "string")
                    local compy = LZW.Compress_Dicts_Prepared(v, prep_id, prep_id_size, nil, prep_is)
                    --assert(LZW.Decompress_Dicts(compy, dictix, nil, fundatoks) == v)
                    --datsize = datsize + #compy
                    
                    self.finalfile[sk] = compy
                    assert(LZW.Decompress_Dicts_Prepared(self.finalfile[sk], dictix, nil, prep_is) == v)
                  end
                end
              else
                for sk, v in pairs(d) do
                  if (type(sk) ~= "string" or not sk:match("__.*")) and type(v) == "string" then
                    assert(type(v) == "string")
                    self.finalfile[sk] = LZW.Compress_Dicts(v, dictix)
                    assert(LZW.Decompress_Dicts(self.finalfile[sk], dictix) == v)
                  end
                end
              end
              
              --fil:write(string.format("%d\t%d\t%d\t%d\n", i, dictsize + datsize, dictsize, datsize))
              
              --print(locale, faction, k, i, #fundatoks, dictsize, datsize, dictsize + datsize)
            --end
            
            --fil:close()
            
            
            --[=[fil = io.open(ofile .. ".gnuplot", "w")
            fil:write("set term png\n")
            fil:write(string.format("set output \"%s.png\"\n", ofile))
            fil:write(string.format([[
                plot \
                  "%s" using 1:2 with lines title 'Total', \
                  "%s" using 1:3 with lines title 'Dict', \
                  "%s" using 1:4 with lines title 'Dat']], ofile, ofile, ofile))
            fil:write("\n")
            fil:close()
            
            os.execute(string.format("gnuplot %s.gnuplot", ofile))]=]
          end
        end
        
        --[[for sk, v in pairs(d) do
          if (type(sk) ~= "string" or not sk:match("__.*")) and type(v) == "string" then
            assert(type(v) == "string")
            self.finalfile[sk] = LZW.Compress_Dicts(v, dictix)
            assert(LZW.Decompress_Dicts(self.finalfile[sk], dictix) == v)
          end
        end]]
      end
      
      if do_compress and do_serialize and segment ~= "flightmasters" then
        --[[Header format:

          Itemid (0 for endnode)
          Offset
          Length
          Rightlink]]

        assert(not self.finalfile.__serialize_index)
        assert(not self.finalfile.__serialize_data)
        
        local ntx = {}
        local intdat = {}
        for k, v in pairs(self.finalfile) do
          if type(k) == "number" then
            if k <= 0 then
              print("Out of bounds:", orig_locale, orig_faction, orig_segment, k)
              ntx[k] = v
            elseif type(v) ~= "string" then
              print("Not a string:", orig_locale, orig_faction, orig_segment, k)
              ntx[k] = v
            else
              assert(#v >= 1)
              table.insert(intdat, {key = k, value = v})
            end
          else
            ntx[k] = v
          end
        end
        
        local data = {}
        local dat_len = 1
        
        table.sort(intdat, function(a, b) return a.key < b.key end)
        
        local function write_adaptint(dest, val)
          assert(type(val) == "number")
          assert(val == math.floor(val))
          
          repeat
            dest:append(math.mod(val, 128), 7)
            dest:append((val >= 128) and 1 or 0, 1)
            val = math.floor(val / 128)
          until val == 0
        end
        
        local function streamout(st, nd)
          local ttx = Bitstream.Output(8)
          if st > nd then
            write_adaptint(ttx, 0)
            return ttx:finish()
          else
            local tindex = math.floor((st + nd) / 2)
            write_adaptint(ttx, intdat[tindex].key)
            write_adaptint(ttx, dat_len)
            write_adaptint(ttx, #intdat[tindex].value - 1)
            Merger.Add(data, intdat[tindex].value)
            dat_len = dat_len + #intdat[tindex].value
            local lhs = streamout(st, tindex - 1)
            local rhs = streamout(tindex + 1, nd)
            write_adaptint(ttx, #lhs)
            return ttx:finish() .. lhs .. rhs
          end
        end
        
        ntx.__serialize_index = streamout(1, #intdat)
        ntx.__serialize_data = Merger.Finish(data)
        
        print("Index is", #ntx.__serialize_index, "data is", #ntx.__serialize_data)
        
        self.finalfile = ntx
      end
      
      Output(string.format("%s/%s", orig_locale, orig_faction), nil, {id = orig_segment, data = self.finalfile})
    end,
  } end)

local fileout = ChainBlock_Create("fileout", {compress},
  function (key) return {
    finalfile = {},
    
    Data = function(self, key, subkey, value, Output)
      assert(value.data, string.format("%s, %s", tostring(value.id), tostring(value.key)))
      assert(value.id)
      
      assert(not self.finalfile[value.id])
      self.finalfile[value.id] = value.data
    end,
    
    Finish = function(self, Output)
      
      local fname = "static"
      
      local locale, faction = key:match("(.*)/(.*)")
      assert(locale and faction)
      if locale == "*" then locale = nil end
      if faction == "*" then faction = nil end      
      
      if locale then
        fname = fname .. "_" .. locale
      end
      if faction then
        fname = fname .. "_" .. faction
      end
      
      fil = io.open(("final/%s.lua"):format(fname), "w")
      fil:write(([=[QuestHelper_File["%s.lua"] = "Development Version"
QuestHelper_Loadtime["%s.lua"] = GetTime()

]=]):format(fname, fname))

      if not locale and not faction then
        fil:write("QHDB = {}", "\n")
      end
      if locale then
        fil:write(([[if GetLocale() ~= "%s" then return end]]):format(locale), "\n")
      end
      if faction then
        fil:write(([[if (UnitFactionGroup("player") == "Alliance" and 1 or 2) ~= %s then return end]]):format(faction), "\n")
      end
      fil:write("\n")
      
      --fil:write("loadstring([[table.insert(QHDB, ")
      fil:write("table.insert(QHDB, ")
      persistence.store(fil, self.finalfile)
      fil:write(")")
      --fil:write(")]])()")
      
      fil:close()
    end,
  } end
)

--[[
*****************************************************************
Error collation
]]

if do_errors then
  local error_collater = ChainBlock_Create("error_collater", {chainhead},
    function (key) return {
      accum = {},
      
      Data = function (self, key, subkey, value, Output)
        assert(value.local_version)
        if not value.toc_version or value.local_version ~= value.toc_version then return end
        local signature
        if value.key ~= "crash" then signature = value.key end
        if not signature then signature = value.message end
        local v = value.local_version
        if not self.accum[v] then self.accum[v] = {} end
        if not self.accum[v][signature] then self.accum[v][signature] = {count = 0, dats = {}, sig = signature, ver = v} end
        self.accum[v][signature].count = self.accum[v][signature].count + 1
        table.insert(self.accum[v][signature].dats, value)
      end,
      
      Finish = function (self, Output)
        for ver, chunk in pairs(self.accum) do
          local tbd = {}
          for _, v in pairs(chunk) do
            table.insert(tbd, v)
          end
          table.sort(tbd, function(a, b) return a.count > b.count end)
          for i, dat in pairs(tbd) do
            dat.count_pos = i
            Output("", nil, dat)
          end
        end
      end
    } end,
    nil, "error"
  )

  do
    local function acuv(tab, ites)
      local sit = ""
      for _, v in pairs(ites) do
        sit = sit .. string.format("%s: %s\n", tostring(v), tostring(tab[v]))
        tab[v] = nil
      end
      return sit
    end
    local function keez(tab)
      local rv = {}
      for k, _ in pairs(tab) do
        table.insert(rv, k)
      end
      return rv
    end
    
    local error_writer = ChainBlock_Create("error_writer", {error_collater},
      function (key) return {
        Data = function (self, key, subkey, value, Output)
          os.execute("mkdir -p intermed/error/" .. value.ver)
          fil = io.open(string.format("intermed/error/%s/%03d-%05d.txt", value.ver, value.count_pos, value.count), "w")
          fil:write(value.sig)
          fil:write("\n\n\n\n")
          
          for _, tab in pairs(value.dats) do
            local prefix = acuv(tab, {"message", "key", "toc_version", "local_version", "game_version", "locale", "timestamp", "mutation"})
            local postfix = acuv(tab, {"stack", "addons"})
            local midfix = acuv(tab, keez(tab))
            
            fil:write(prefix)
            fil:write("\n")
            fil:write(midfix)
            fil:write("\n")
            fil:write(postfix)
            fil:write("\n\n\n")
          end
          
          fil:close()
        end
      } end
    )
  end
end

if ChainBlock_Work() then return end

local count = 1

local function readdir()
  local pip = io.popen(("find data/08 -type f | head -n %s | tail -n +%s"):format(e or 1000000000, s or 0))
  local flist = pip:read("*a")
  pip:close()
  local filz = {}
  for f in string.gmatch(flist, "[^\n]+") do
    if not s or count >= s then table.insert(filz, {fname = f, id = count}) end
    count = count + 1
    if e and count > e then break end
  end
  return filz
end

local filout = readdir("data/08")

for k, v in pairs(filout) do
  --print(string.format("%d/%d: %s", k, #filz, v.fname))
  chainhead:Insert(v.fname, nil, {fileid = v.id})
end

print("Finishing with " .. tostring(count - 1) .. " files")
chainhead:Finish()

check_semiass_failure()
