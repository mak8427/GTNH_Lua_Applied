-- Basic imports
sides = require("sides")
component = require("component")
string = require("string")
os = require("os")

-- Change to the address of your adapter and redstone io
-- rs = component.proxy("b029eedf-5119-4aea-91d2-84e3c2e0e4e8")

-- List of items to watch
watchitems = {
  ["minecraft:stone"] = 100000,
}

local component = require("component")

print("[DEBUG] Checking AE2 component availability...")
local ae2
if component.isAvailable("me_controller") then
    ae2 = component.me_controller
    print("[DEBUG] Connected to ME Controller.")
elseif component.isAvailable("me_interface") then
    ae2 = component.me_interface
    print("[DEBUG] Connected to ME Interface.")
else
    print("[ERROR] No ME controller or interface found. Exiting.")
    os.exit()
end

-- Infinite loop
while true do
  print("\n[DEBUG] Starting new loop cycle...")

  -- Check redstone signal (stubbed)
  rs_input = 100
  print(string.format("[DEBUG] Redstone input is %d", rs_input))

  -- Check if any CPUs are busy
  print("[DEBUG] Fetching AE2 CPU usage...")
  cpus = ae2.getCpus()


  busy = true
  for i in ipairs(cpus) do
    print(string.format("[DEBUG] CPU %d busy: %s", i, tostring(cpus[i].busy)))
    if cpus[i].busy == false then
      busy = false
      break
    end
  end


  if rs_input > 0 and busy == false then
    print("[DEBUG] System is idle and ready for crafting check.")

    for itemname, keepsize in pairs(watchitems) do
      print("\n----------------------------------------")
      print(string.format("[DEBUG] Checking item: %s | Desired count: %d", itemname, keepsize))

      local damage = 0
      if string.find(itemname, "/") ~= nil then
        delim = string.find(itemname, "/")
        len = string.len(itemname)
        damage = string.sub(itemname, delim + 1, len)
        itemname = string.sub(itemname, 1, delim - 1)
        print(string.format("[DEBUG] Parsed item: %s | Metadata: %s", itemname, damage))
      else
        print("[DEBUG] No metadata found; using 0")
      end

      print("[DEBUG] Querying AE2 network for item...")
      item_in_network = ae2.getItemsInNetwork({name = itemname, damage = tonumber(damage)})[1]

      local stocksize = 0
      if item_in_network == nil then
        print("[DEBUG] Item not found in network. Assuming 0 in stock.")
        stocksize = 0
      else
        stocksize = item_in_network.size
        print(string.format("[DEBUG] Current stock: %d", stocksize))
      end

      if keepsize > stocksize then
        reqsize = keepsize - stocksize
        print(string.format("[DEBUG] Need to craft %d more of %s/%s", reqsize, itemname, damage))

        recipe = ae2.getCraftables({name = itemname, damage = tonumber(damage)})[1]

        if recipe == nil then
          print(string.format("[ERROR] No recipe found for %s/%s", itemname, damage))
        else
          print(string.format("[DEBUG] Crafting %d of %s/%s...", reqsize, itemname, damage))
          monitor = recipe.request(reqsize)

          -- Monitor crafting progress
          while not monitor.isDone() and not monitor.isCanceled() do
            print("[DEBUG] Crafting in progress...")
            os.sleep(5)
          end

          if monitor.isCanceled() then
            print(string.format("[WARNING] Crafting of %s/%s was canceled.", itemname, damage))
          else
            print(string.format("[DEBUG] Crafting complete: %d of %s/%s", reqsize, itemname, damage))
          end
        end
      else
        print(string.format("[DEBUG] Stock sufficient: %d / %d", stocksize, keepsize))
      end

      -- Delay to reduce network hammering
      os.sleep(5)
    end
  else
    print("[DEBUG] Skipping crafting check. Either redstone signal is off or system is busy.")
  end

  -- Main loop delay
  os.sleep(30)
end
