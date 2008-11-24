QuestHelper_File["collect_zone.lua"] = "Development Version"

local debug_output = false
if QuestHelper_File["collect_traveled.lua"] == "Development Version" then debug_output = true end

local QHCZ

local GetLoc
local Merger

local function DoZoneUpdate(label, debugverbose)
  local zname = string.format("%s@@%s@@%s", GetZoneText(), GetRealZoneText(), GetSubZoneText()) -- I don't *think* any zones will have a @@ in them :D
  if zname == "@@@@" then return end -- denied
  if not QHCZ[zname] then QHCZ[zname] = {} end
  if not QHCZ[zname][label] then QHCZ[zname][label] = {} end
  
  if debugverbose and debug_output then
    QuestHelper:TextOut("zoneupdate " .. zname .. " type " .. label)
  end
  
  QHCZ[zname].mapname = GetMapInfo()
  local loc = GetLoc()
  Merger.Add(QHCZ[zname][label], loc)
end

local function OnEvent()
  DoZoneUpdate("border", true)
end

local lastupdate = 0
local function OnUpdate()
  if lastupdate + 15 <= GetTime() then
    DoZoneUpdate("update")
    lastupdate = GetTime()
  end
end

function QH_Collect_Zone_Init(QHCData, API)
  if not QHCData.zone then QHCData.zone = {} end
  QHCZ = QHCData.zone
  
  API.Registrar_EventHook("ZONE_CHANGED", OnEvent)
  API.Registrar_EventHook("ZONE_CHANGED_INDOORS", OnEvent)
  API.Registrar_EventHook("ZONE_CHANGED_NEW_AREA", OnEvent)
  
  API.Registrar_OnUpdateHook(OnUpdate)
  
  GetLoc = API.Callback_LocationBolusCurrent
  QuestHelper: Assert(GetLoc)
  
  Merger = API.Utility_Merger
  QuestHelper: Assert(Merger)
end