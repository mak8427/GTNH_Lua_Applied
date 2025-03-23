-- Basic imports
sides = require("sides")
component = require("component")
string = require("string")
os = require("os")
internet = require("internet") -- For webclock functions

-- Real-world time functions
function webclock()
    local handle = internet.request("http://www.rootdir.org/webclock.php?tz=Europe/Rome&locale=pt_BR.UTF-8")
    local result = ""
    for chunk in handle do
        result = chunk
    end
    local datetime = os.time({
        year = result:sub(1, 4),
        month = result:sub(6, 7),
        day = result:sub(9, 10),
        hour = result:sub(12, 13),
        min = result:sub(15, 16),
        sec = result:sub(18, 19)
    })
    return datetime
end

function time_format(datetime)
    return os.date("%Y-%m-%d %H:%M:%S", datetime)
end

---------------------------------------------------------------------
-- Read CSV file and parse watchlist
local function readCSVFile(filename)
    local file = io.open(filename, "r")
    if not file then
        print("[ERROR] Could not open file " .. filename)
        os.exit()
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Parse CSV text into a table.
-- Each line: itemID,desired stock,batch size
local function parseWatchItems(csv)
    local items = {}
    for line in csv:gmatch("[^\r\n]+") do
        local id, desired, batch = line:match("([^,]+),([^,]+),([^,]+)")
        if id and desired and batch then
            items[id] = { desired = tonumber(desired), batch = tonumber(batch) }
        end
    end
    return items
end

-- Read watchlist from file "watchlist.csv"
local csvContent = readCSVFile("watchlist.csv")
local watchitems = parseWatchItems(csvContent)
---------------------------------------------------------------------

-- Get AE2 component
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

-- Logging system: Save current AE2 network items to a file.
local function logNetworkItems()
    local logFile = "ae2_item_log.txt"
    local file = io.open(logFile, "w")
    if not file then
        print("[ERROR] Failed to open log file for writing.")
        return
    end

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
end

-- Utility: Parse full item string into (name, damage)
local function parseItemName(fullName)
    local pos = string.find(fullName, "/")
    if pos then
        local name = string.sub(fullName, 1, pos - 1)
        local damage = tonumber(string.sub(fullName, pos + 1))
        return name, damage
    else
        return fullName, 0
    end
end

-- Helper: Return the index of the first free CPU
local function getFreeCPU()
    local cpus = ae2.getCpus()
    for i, cpu in ipairs(cpus) do
        print(string.format("CPU #%d - Name: %s - Busy: %s", i, cpu.name or "Unnamed", tostring(cpu.busy)))
        if not cpu.busy then
            return i
        end
    end
    return "N/A"
end

-- Function to trigger crafting requests for items that are short in stock.
-- Only one active request per item is allowed.
local function checkCrafting()
    local monitors = {}
    for fullItemName, data in pairs(watchitems) do
        local desiredCount = data.desired
        local batchSize = data.batch
        print("\n----------------------------------------")
        print(string.format("[DEBUG] Checking item: %s | Desired count: %d | Batch size: %d", fullItemName, desiredCount,
            batchSize))

        local itemname, damage = parseItemName(fullItemName)
        print(string.format("[DEBUG] Parsed item: %s | Metadata: %s", itemname, tostring(damage)))

        print("[DEBUG] Querying AE2 network for item...")
        local item_in_network = ae2.getItemsInNetwork({ name = itemname, damage = damage })[1]

        local currentStock = 0
        local label = fullItemName
        if item_in_network then
            currentStock = item_in_network.size
            if item_in_network.label then
                label = item_in_network.label
            end
            print(string.format("[DEBUG] Current stock: %d (Label: %s)", currentStock, label))
        else
            print("[DEBUG] Item not found in network. Assuming 0 in stock.")
        end

        if desiredCount > currentStock then
            local difference = desiredCount - currentStock
            local reqsize = math.min(difference, batchSize)
            print(string.format("[DEBUG] Need to craft %d more (difference: %d) of %s (Label: %s)", reqsize, difference,
                itemname, label))
                    local recipe = ae2.getCraftables({ name = itemname, damage = damage })[1]
            if recipe then
                print(string.format("[DEBUG] Requesting crafting of %d of %s (Label: %s)...", reqsize, itemname, label))
                local monitor = recipe.request(reqsize)
                local freeCPU = getFreeCPU() -- Get free CPU at the time of the request
                monitors[fullItemName] = {
                    monitor = monitor,
                    startTime = webclock(),
                    totalRequested = reqsize,
                    initialStock = currentStock,
                    queryName = itemname,
                    queryDamage = damage,
                    label = label,
                    cpuNum = freeCPU
                }
                print(string.format("[DEBUG] Craft initiated at %s on CPU %s for %s",
                    time_format(monitors[fullItemName].startTime), tostring(freeCPU), label))
            else
                print(string.format("[ERROR] No recipe found for %s/%s", itemname, tostring(damage)))
            end
        else
            print(string.format("[DEBUG] Stock sufficient: %d / %d", currentStock, desiredCount))
        end

        os.sleep(0.1) -- Short delay between requests
    end
    return monitors
end

-- Function to monitor crafting requests concurrently.
local function monitorCrafting(monitors)
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

            -- Re-query current stock for the item.
            local currentItem = ae2.getItemsInNetwork({ name = data.queryName, damage = data.queryDamage })[1]
            local currentStock = currentItem and currentItem.size or 0
            local produced = currentStock - initialStock
            if produced < 0 then produced = 0 end
            local remaining = totalRequested - produced
            if remaining < 0 then remaining = 0 end

            if unfinished[itemKey] then
                if monitor.isCanceled() then
                    print(string.format("[WARNING] Crafting of %s CPU: %s was canceled after %d seconds.",
                        data.label, tostring(data.cpuNum), elapsed))
                    unfinished[itemKey] = nil
                elseif monitor.isDone() then
                    print(string.format(
                        "[DEBUG] Crafting of %s  CPU: %s completed successfully after %d seconds! Produced: %d, Remaining: %d",
                        data.label, tostring(data.cpuNum), elapsed, produced, remaining))
                    unfinished[itemKey] = nil
                else
                    print(string.format(
                        "[DEBUG] Crafting in progress for %s  CPU: %s ... Started at %s, Elapsed: %d seconds, Produced: %d, Remaining: %d",
                        data.label, tostring(data.cpuNum), time_format(startTime), elapsed, produced, remaining))
                end
            end
        end
        os.sleep(5)
    end
end

-- Main loop function
local function mainLoop()
    while true do
        print("\n[DEBUG] Starting new loop cycle...")
        -- Check redstone signal (stubbed)
        local rs_input = 100
        print(string.format("[DEBUG] Redstone input is %d", rs_input))

        -- Check CPU usage using getFreeCPU()
        local currentFreeCPU = getFreeCPU()
        if rs_input > 0 and currentFreeCPU ~= "N/A" then
            print("[DEBUG] System is idle and ready for crafting check.")
            local monitors = checkCrafting()
            monitorCrafting(monitors)
        else
            print("[DEBUG] Skipping crafting check. Either redstone signal is off or no free CPUs available.")
        end

        -- Wait before starting the next cycle
        os.sleep(30)
    end
end

-- Log the network items once before starting the main loop
logNetworkItems()

-- Start the main loop
mainLoop()
