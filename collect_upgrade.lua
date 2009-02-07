QuestHelper_File["collect_upgrade.lua"] = "Development Version"
QuestHelper_Loadtime["collect_upgrade.lua"] = GetTime()

function QH_Collector_Upgrade()
  if QuestHelper_Collector_Version == 1 then
    -- We basically just want to clobber all our old route data, it's not worth storing - it's all good data, it's just that we don't want to preserve relics of the old location system.
    for _, v in pairs(QuestHelper_Collector) do
      v.traveled = nil
    end
    
    QuestHelper_Collector_Version = 2
  end
  
  if QuestHelper_Collector_Version == 2 then
    -- Originally I split the zones based on locale. Later I just split everything based on locale. Discarding old data rather than doing the gymnastics needed to preserve it.
    -- This is turning into a routine. :D
    for _, v in pairs(QuestHelper_Collector) do
      v.zone = nil
    end
    
    QuestHelper_Collector_Version = 3
  end
  
  if QuestHelper_Collector_Version == 3 then
    -- Screwed up the item collection code in instances. Obliterate old data, try again.
    for locale, data in pairs(QuestHelper_Collector) do
      if data.item then
        for id, dat in pairs(data.item) do
          dat.equip_no = nil
          dat.equip_yes = nil
        end
      end
    end
    
    QuestHelper_Collector_Version = 4
  end
  
  if QuestHelper_Collector_Version == 4 then
    -- Munged the shops rather badly. Whoopsydaisy.
    for locale, data in pairs(QuestHelper_Collector) do
      if data.monster then
        local nv = {}
        for id, dat in pairs(data.monster) do
          if type(dat) == "string" then
            nv[id] = dat
          end
        end
        data.monster = nv
      end
    end
    
    QuestHelper_Collector_Version = 5
  end
end
