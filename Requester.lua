-- Basic imports
sides = require("sides")
component = require("component")
string = require("string")
os = require("os")

-- Change to the address of your adapter and redstone io
rs = component.proxy("b029eedf-5119-4aea-91d2-84e3c2e0e4e8")
ae2 = component.proxy("c2696567-82f6-4c15-80de-b78e275f47c1")


-- List of items to watch. Enable advanced tooltips to get the itemnames (F3+H)
-- Add /X to end of item to get specific items based on metadata
-- Each item in this list needs to have a recipe in the system to craft it.
-- Below are most of the mystical aggriculture items from PO3
watchitems = {
  ["minecraft:stone"] = 100000,
}


-- Infinite loop, can use alt-ctrl-c to break
while true do

  -- Check to see if we're getting redstone input from the top.
  rs_input = rs.getInput(sides.top)

  -- Check if any CPU's are currently being used.
  cpus = ae2.getCpus()
  busy = false
  for i in ipairs(cpus) do busy = cpus[i].busy or busy end

  -- If no CPU's are being used, and we're not getting a redstone signal from manual kill lever
  -- then we will run a loop of itemchecking.
  if rs_input > 0 and busy == false then

    -- Iterate through each item in watchitems table
    for itemname,keepsize in pairs(watchitems) do

      -- String parsing to get out the damage/metadata value from our string
      -- thermalfoundation:material/2048 becomes
      --   itemname = thermalfoundation:material
      --   damage = 2048
      -- Anything without a metadata specified is 0
      if string.find(itemname,"/") ~= nil then
        delim = string.find(itemname, "/")
        len = string.len(itemname)
        damage = string.sub(itemname, delim + 1, len )
        itemname = string.sub(itemname, 1 , delim - 1 )
      else
        damage = 0
      end

      -- Query AE2 to find items in network
      item_in_network = ae2.getItemsInNetwork({name = itemname, damage = tonumber(damage)})[1]

      -- If response is nil, the item doesn't exist in the network, so we have 0
      if item_in_network == nil then
        stocksize = 0
      else
        stocksize = item_in_network.size
      end

      -- If we have less than we want...
      if keepsize > stocksize then
        reqsize = keepsize - stocksize

        -- This checks the AE2 system to find the crafting recipe with that name/damage
        recipe = ae2.getCraftables({name = itemname, damage = tonumber(damage)})[1]

        -- Recipe not found, probably a typo or you need to set up the recipe
        if recipe == nil then
          print(string.format("No recipe found for %s / %s, recipe not found", itemname, damage))
        else
          print(string.format("%s/%s: Have %s, Need %s ", itemname, damage, stocksize, keepsize))

          -- Request that the AE2 system craft the recipe. Returns a monitor object
          -- Note that if we don't have enough items in the system to actually craft the amount requested
          -- we have no way of finding that out, the API just tells us that the craft was done immediately.
          monitor = recipe.request(reqsize)

          -- Wait for the craft to complete
          while monitor.isDone() == false and monitor.isCanceled() == false do
            os.sleep(5)
          end
          print(string.format("%s/%s: crafted %s", itemname,damage,reqsize))
        end
      end

      -- Wait a bit so as not to hammer to the system
      os.sleep(5)
    end
  end

  -- Wait a bit so as not to hammer to the system
  os.sleep(30)
end