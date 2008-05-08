local cartographer_cb
local cartographer_wp

local QuestHelperPoint

local function cartographer_wp_update(c, z, x, y, desc)
  if cartographer_wp then
    cartographer_wp:Cancel()
  end
  
  if c then
    cartographer_wp = QuestHelperPoint:new(c, z, x, y, desc)
    Cartographer_Waypoints:AddWaypoint(cartographer_wp)
  end
end

function QuestHelper:EnableCartographer()
  if Cartographer_Waypoints then
    if not QuestHelperPoint then
      QuestHelperPoint = Waypoint:new()
      QuestHelperPoint.ShowOnMap = false
      
      function QuestHelperPoint:init(c, z, x, y, desc)
        self.x, self.y, self.task = x, y, desc
        
        local zone = select(z, GetMapZones(c))
        
        if Rock then
          local LibBabble = Rock("LibBabble-Zone-3.0", false, true)
          if LibBabble then
            zone = LibBabble:GetReverseLookupTable()[zone]
          end
        end
        
        self.Zone = zone
      end

      function QuestHelperPoint:Cancel()
        self.task = nil
        
        if cartographer_wp == self then
          cartographer_wp = nil
        end
        
        Waypoint.Cancel(self)
      end

      function QuestHelperPoint:ToString()
        return self.task or "Waypoint"
      end
    end
    
    if not cartographer_cb then
      cartographer_cb = QuestHelper:AddWaypointCallback(cartographer_wp_update)
    end
  end
end

function QuestHelper:DisableCartographer()
  if cartographer_cb then
    if cartographer_wp then
      cartographer_wp:Cancel()
    end
    
    QuestHelper:RemoveWaypointCallback(cartographer_cb)
    cartographer_cb = nil
  end
end