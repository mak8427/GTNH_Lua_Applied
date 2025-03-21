-- Basic imports
sides = require("sides")
component = require("component")
string = require("string")
os = require("os")
internet = require("internet")  -- Added for webclock functions

-- Function to get Real World time
function webclock()
  local handle = internet.request("http://www.rootdir.org/webclock.php?tz=Europe/Rome&locale=pt_BR.UTF-8")
  local result = ""
  for chunk in handle do
    result = chunk
  end
  local datetime = os.time({
    year = result:sub(1,4),
    month = result:sub(6,7),
    day = result:sub(9,10),
    hour = result:sub(12,13),
    min = result:sub(15,16),
    sec = result:sub(18,19)
  })
  return datetime
end

function time_format(datetime)
  return os.date("%Y-%m-%d %H:%M:%S", datetime)
end
-- List of items to watch
watchitems = {
    ["minecraft:stone"] = 15000,
    ["gregtech:gt.metaitem.01/11085"] = 30000
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

-- Logging system
local logFile = "ae2_item_log.txt"

-- Open file for writing
local file = io.open(logFile, "w")
if not file then
    print("[ERROR] Failed to open log file for writing.")
    return
end

print("[DEBUG] Listing all items in AE2 Network... Writing to log.")

file:write("AE2 Network Item List:\n")
file:write("---------------------------------\n")

local items = ae2.getItemsInNetwork()

if #items == 0 then
    file:write("[ERROR] No items found in AE2 Network.\n")
    print("[ERROR] No items found in AE2 Network.")
else
    for _, item in ipairs(items) do
        local line = string.format("%s/%d - %d in stock\n", item.name, item.damage, item.size)
        file:write(line)
    end
end

file:write("---------------------------------\n")
file:close()

print("[DEBUG] Item list saved to " .. logFile)

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

        local monitors = {}  -- Table to store crafting monitors along with debug info

        -- Request crafting for each item if stock is low
        for fullItemName, keepsize in pairs(watchitems) do
            print("\n----------------------------------------")
            print(string.format("[DEBUG] Checking item: %s | Desired count: %d", fullItemName, keepsize))

            local damage = 0
            local itemname = fullItemName
            if string.find(fullItemName, "/") ~= nil then
                local delim = string.find(fullItemName, "/")
                local len = string.len(fullItemName)
                damage = string.sub(fullItemName, delim + 1, len)
                itemname = string.sub(fullItemName, 1, delim - 1)
                print(string.format("[DEBUG] Parsed item: %s | Metadata: %s", itemname, damage))
            else
                print("[DEBUG] No metadata found; using 0")
            end

            print("[DEBUG] Querying AE2 network for item...")
            local item_in_network = ae2.getItemsInNetwork({ name = itemname, damage = tonumber(damage) })[1]

            local stocksize = 0
            if item_in_network == nil then
                print("[DEBUG] Item not found in network. Assuming 0 in stock.")
                stocksize = 0
            else
                stocksize = item_in_network.size
                print(string.format("[DEBUG] Current stock: %d", stocksize))
            end

            if keepsize > stocksize then
                local reqsize = keepsize - stocksize
                print(string.format("[DEBUG] Need to craft %d more of %s/%s", reqsize, itemname, damage))

                local recipe = ae2.getCraftables({ name = itemname, damage = tonumber(damage) })[1]

                if recipe == nil then
                    print(string.format("[ERROR] No recipe found for %s/%s", itemname, damage))
                else
                    print(string.format("[DEBUG] Requesting crafting of %d of %s/%s...", reqsize, itemname, damage))
                    local monitor = recipe.request(reqsize)
                    -- Store monitor along with start time (using webclock), requested quantity, initial stock, and query info
                    monitors[fullItemName] = {
                        monitor = monitor,
                        startTime = webclock(),
                        totalRequested = reqsize,
                        initialStock = stocksize,
                        queryName = itemname,
                        queryDamage = tonumber(damage)
                    }
                    print(string.format("[DEBUG] Craft initiated at %s", time_format(monitors[fullItemName].startTime)))
                end
            else
                print(string.format("[DEBUG] Stock sufficient: %d / %d", stocksize, keepsize))
            end

            -- Short delay between requests to reduce network load
            os.sleep(2)
        end

        -- Monitor all crafting requests concurrently
        local unfinished = {}
        for key, _ in pairs(monitors) do
            unfinished[key] = true
        end

        while next(unfinished) do
            for itemKey, data in pairs(monitors) do
                local monitor = data.monitor
                local startTime = data.startTime
                local totalRequested = data.totalRequested
                local initialStock = data.initialStock
                local elapsed = webclock() - startTime

                -- Re-query the current stock for this item using the stored query info
                local currentItem = ae2.getItemsInNetwork({ name = data.queryName, damage = data.queryDamage })[1]
                local currentStock = 0
                if currentItem ~= nil then
                    currentStock = currentItem.size
                end

                local produced = currentStock - initialStock
                if produced < 0 then produced = 0 end
                local remaining = totalRequested - produced
                if remaining < 0 then remaining = 0 end

                if unfinished[itemKey] then
                    if monitor.isCanceled() then
                        print(string.format("[WARNING] Crafting of %s was canceled after %d seconds.", itemKey, elapsed))
                        unfinished[itemKey] = nil
                    elseif monitor.isDone() then
                        print(string.format("[DEBUG] Crafting of %s completed successfully after %d seconds!", itemKey, elapsed))
                        unfinished[itemKey] = nil
                    else
                        print(string.format("[DEBUG] Crafting in progress for %s... Started at %s, Elapsed: %d seconds, Produced: %d, Remaining: %d",
                            itemKey, time_format(startTime), elapsed, produced, remaining))
                    end
                end
            end
            os.sleep(5)  -- Wait a bit before checking again
        end

    else
        print("[DEBUG] Skipping crafting check. Either redstone signal is off or system is busy.")
    end

    -- Main loop delay
    os.sleep(30)
end