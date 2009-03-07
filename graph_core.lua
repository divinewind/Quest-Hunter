QuestHelper_File["graph_core.lua"] = "Development Version"
QuestHelper_Loadtime["graph_core.lua"] = GetTime()

-- Alright so what's the interface here
-- There's the obvious "find a path from A to B"
-- function QH_Graph_Pathfind(st, nd, make_path)
-- Right now, we're pretending that the world consists of infinite planes with links between them. That's where the whole "between-zone" thing occurs. So one way or another, we need to add links. We'll use name as an identifier so we can get rid of flight paths links later, and the coords will include a plane ID number.
-- function QH_Graph_Plane_Makelink(name, coord1, coord2, cost)
-- And then we need a way to get rid of links, so:

local function xydist(st, nd)
  QuestHelper: Assert(st.p == nd.p)
  local dx, dy = st.x - nd.x, st.y - nd.y
  return math.sqrt(dx * dx + dy * dy)
end

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

-- incremented on each graph iteration, so we don't have to clear everything. "GRaph ID" :D
local grid = 0

-- Plane format: each plane contains an array of nodes that exist in that plane.
-- Each node contains both its parent ID and its coordinates within that plane. It may contain a node it links to, along with cost.
local plane = {}

function QH_Graph_Pathfind(st, nd, make_path)
  QuestHelper: Assert(not make_path)
  
  return QH_Graph_Pathmultifind(st, {nd}, make_path)[1]
end

function QH_Graph_Pathmultifind(st, nda, make_path)
  QuestHelper: Assert(not make_path)

  local out = {}
  local remaining = 0 -- Right now this isn't actually updated
  
  for k, v in ipairs(nda) do
    if st.p == v.p then
      out[k] = xydist(st, v)
    else
      if plane[v.p] then
        table.insert(plane[v.p], {x = v.x, y = v.y, p = v.p, goal = k})
        remaining = remaining + 1
      end
    end
  end
  
  local dijheap = {}
  if plane[st.p] then
    for _, v in ipairs(plane[st.p]) do
      if v.link then
        QuestHelper: Assert(not v.goal)
        local dst = xydist(st, v)
        v.scan_id = grid
        v.scan_cost = dst
        heap_insert(dijheap, {c = dst, n = v})
      end
    end
  end
  
  while remaining > 0 and #dijheap > 0 do
    local cdj = heap_extract(dijheap)
    print(string.format("Extracted cost %f/%s pointing at %f/%f/%d", cdj.c, tostring(cdj.n.scan_cost), cdj.n.x, cdj.n.y, cdj.n.p))
    QuestHelper: Assert(cdj.n.link)
    if cdj.n.scan_cost == cdj.c then  -- if we've modified it since then, don't bother
      local linkto = cdj.n.link
      local basecost = cdj.c + cdj.n.link_cost
      print("enter alpha")
      if linkto.scan_id ~= grid or linkto.scan_cost > basecost then
        print("enter beta")
        for _, v in ipairs(plane[linkto.p]) do
          if v.goal then
            -- One way or another, we gotta calculate this.
            local goalcost = basecost + xydist(linkto, v)
            if not out[v.goal] or out[v.goal] > goalcost then
              out[v.goal] = goalcost
            end
          elseif v.link and (v.scan_id ~= grid or v.scan_cost > basecost) then
            local goalcost = basecost + xydist(linkto, v)
            if not v.scan_cost or v.scan_cost > goalcost then
              v.scan_id = grid
              v.scan_cost = goalcost
              heap_insert(dijheap, {c = goalcost, n = v})
            end
          end
        end
      end
    end
  end
  
  for k, v in ipairs(nda) do
    if plane[v.p] and plane[v.p][#plane[v.p]].goal then   -- might not be the exact one, but we'll remove 'em all once we get there anyway :D
      table.remove(plane[v.p])
    end
  end
  
  grid = grid + 1
  QuestHelper: Assert(grid < 1000000000) -- if this ever triggers I will be amazed
  
  return out
end

function QH_Graph_Plane_Makelink(name, coord1, coord2, cost)
  QuestHelper: Assert(name)
  QuestHelper: Assert(coord1)
  QuestHelper: Assert(coord2)
  QuestHelper: Assert(cost)
  
  if not plane[coord1.p] then plane[coord1.p] = {} end
  if not plane[coord2.p] then plane[coord2.p] = {} end
  
  local node1 = {x = coord1.x, y = coord1.y, p = coord1.p, link_cost = cost, name = name}
  local node2 = {x = coord2.x, y = coord2.y, p = coord2.p, link_cost = cost, name = name}
  
  node1.link = node2
  node2.link = node1
  
  table.insert(plane[node1.p], node1)
  table.insert(plane[node2.p], node2)
end

function QH_Graph_Plane_Destroylinks(name)
end

-- let's put up some unittests
QuestHelper: Assert(QH_Graph_Pathfind({x = 10, y = 10, p = 0}, {x = 13, y = 14, p = 0}) == 5)
QuestHelper: Assert(QH_Graph_Pathfind({x = 10, y = 10, p = 0}, {x = 13, y = 14, p = 1}) == nil)
