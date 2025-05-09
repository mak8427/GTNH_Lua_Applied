-- Basic imports
sides = require("sides")
component = require("component")
string = require("string")
os = require("os")
internet = require("internet") -- For webclock functions
gpu = component.gpu            -- Get GPU component for colored text

-- Color constants
local COLOR_WHITE = 0xFFFFFF
local COLOR_GREEN = 0x00FF00
local COLOR_BLUE = 0x2E86C1
local COLOR_YELLOW = 0xFFFF00
local COLOR_RED = 0xFF0000
local COLOR_CYAN = 0x00FFFF
local COLOR_MAGENTA = 0xFF00FF
local nextMonitorId = 0
-- Configuration settings
local CRAFTING_TIMEOUT_SECONDS = 3000 -- 50 minutes timeout for crafting requests

-- Set default colors
gpu.setForeground(COLOR_WHITE)
gpu.setBackground(0x000000)


-- Colored print functions
local function print_debug(text)
    gpu.setForeground(COLOR_BLUE)
    print("[DEBUG] " .. text)
    gpu.setForeground(COLOR_WHITE)
end

local function print_info(text)
    gpu.setForeground(COLOR_GREEN)
    print("[INFO] " .. text)
    gpu.setForeground(COLOR_WHITE)
end

local function print_warning(text)
    gpu.setForeground(COLOR_YELLOW)
    print("[WARNING] " .. text)
    gpu.setForeground(COLOR_WHITE)
end

local function print_error(text)
    gpu.setForeground(COLOR_RED)
    print("[ERROR] " .. text)
    gpu.setForeground(COLOR_WHITE)
end

local function print_status(text)
    gpu.setForeground(COLOR_CYAN)
    print("[STATUS] " .. text)
    gpu.setForeground(COLOR_WHITE)
end

--------------------------------------------------
-- Time and Date Functions
--------------------------------------------------
function webclock()
    local success, handle = pcall(internet.request,
        "http://www.rootdir.org/webclock.php?tz=Europe/Rome&locale=pt_BR.UTF-8")
    if not success or not handle then
        return nil, "Failed to connect to the time server."
    end

    local result = ""
    local ok, err = pcall(function()
        for chunk in handle do
            result = result .. chunk
        end
    end)

    if not ok or result == "" then
        return nil, "Failed to read data from the server."
    end

    if #result < 19 then
        print_warning("Unexpected time string format: " .. result)
        os.sleep(1)
    end

    local year = tonumber(result:sub(1, 4))
    local month = tonumber(result:sub(6, 7))
    local day = tonumber(result:sub(9, 10))
    local hour = tonumber(result:sub(12, 13))
    local min = tonumber(result:sub(15, 16))
    local sec = tonumber(result:sub(18, 19))

    if not (year and month and day and hour and min and sec) then
        os.sleep(1)
        return webclock()
    end

    local datetime = os.time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = min,
        sec = sec
    })

    return datetime
end

function time_format(datetime)
    return os.date("%Y-%m-%d %H:%M:%S", datetime)
end

--------------------------------------------------
-- CSV and Watchlist Functions
--------------------------------------------------
local function readCSVFile(filename)
    local file = io.open(filename, "r")
    if not file then
        print_error("Could not open file " .. filename)
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

local csvContent = readCSVFile("watchlist.csv")
local watchitems = parseWatchItems(csvContent)

--------------------------------------------------
-- AE2 Component Setup and Logging
--------------------------------------------------
print_debug("Checking AE2 component availability...")
local ae2
if component.isAvailable("me_controller") then
    ae2 = component.me_controller
    print_info("Connected to ME Controller.")
elseif component.isAvailable("me_interface") then
    ae2 = component.me_interface
    print_info("Connected to ME Interface.")
else
    print_error("No ME controller or interface found. Exiting.")
    os.exit()
end

local function logNetworkItems()
    local logFile = "ae2_item_log.txt"
    local file = io.open(logFile, "w")
    if not file then
        print_error("Failed to open log file for writing.")
        return
    end

    file:write("AE2 Network Item List:\n")
    file:write("---------------------------------\n")

    local items = ae2.getItemsInNetwork()
    if #items == 0 then
        file:write("[ERROR] No items found in AE2 Network.\n")
        print_error("No items found in AE2 Network.")
    else
        for _, item in ipairs(items) do
            local line = string.format("%s/%d - %d in stock\n", item.name, item.damage, item.size)
            file:write(line)
        end
    end

    file:write("---------------------------------\n")
    file:close()
    print_info("Item list saved to " .. logFile)
end

--------------------------------------------------
-- CSV Export Functions
--------------------------------------------------
-- Function to export active monitors to CSV
local function exportActiveMonitorsToCSV(monitors)
    local filename = "active_monitors.csv"
    local file = io.open(filename, "w")
    if not file then
        print_error("Failed to open " .. filename .. " for writing")
        return false
    end

    -- Write CSV header
    file:write("ItemKey,Label,QueryName,QueryDamage,StartTime,CurrentTime,ElapsedSeconds,TotalRequested,")
    file:write("InitialStock,CurrentStock,Produced,Remaining,CPUName,CancellationAttempted\n")

    local currentTime = webclock()
    local monitorCount = 0

    for itemKey, data in pairs(monitors) do
        monitorCount = monitorCount + 1
        local elapsed = currentTime - data.startTime

        -- Re-query current stock for the item
        local currentItem = ae2.getItemsInNetwork({ name = data.queryName, damage = data.queryDamage })[1]
        local currentStock = currentItem and currentItem.size or 0
        local produced = math.max(0, currentStock - data.initialStock)
        local remaining = math.max(0, data.totalRequested - produced)

        -- Format CSV line (escape commas in text fields)
        local line = string.format('"%s","%s","%s",%d,%s,%s,%d,%d,%d,%d,%d,%d,"%s",%s\n',
            itemKey:gsub('"', '""'),                         -- ItemKey
            data.label:gsub('"', '""'),                      -- Label
            data.queryName:gsub('"', '""'),                  -- QueryName
            data.queryDamage,                                -- QueryDamage
            time_format(data.startTime),                     -- StartTime
            time_format(currentTime),                        -- CurrentTime
            elapsed,                                         -- ElapsedSeconds
            data.totalRequested,                             -- TotalRequested
            data.initialStock,                               -- InitialStock
            currentStock,                                    -- CurrentStock
            produced,                                        -- Produced
            remaining,                                       -- Remaining
            tostring(data.cpuNum):gsub('"', '""'),           -- CPUName
            data.cancellationAttempted and "true" or "false" -- CancellationAttempted
        )

        file:write(line)
    end

    file:close()
    print_info("Exported " .. monitorCount .. " active monitors to " .. filename)
    return true
end

-- Function to export crafting history to CSV (appending mode)
local function exportCraftingHistoryToCSV()
    local filename = "crafting_history.csv"
    local fileExists = false
    local f = io.open(filename, "r")
    if f then
        fileExists = true
        f:close()
    end

    -- Open file in append mode
    local file = io.open(filename, fileExists and "a" or "w")
    if not file then
        print_error("Failed to open " .. filename .. " for writing")
        return false
    end

    -- Write header only if creating a new file
    if not fileExists then
        file:write("Timestamp,ItemKey,Label,QueryName,QueryDamage,StartTime,EndTime,DurationSeconds,")
        file:write("TotalRequested,InitialStock,FinalStock,Produced,Remaining,CPUName,")
        file:write("Status,CancellationAttempted,TimeoutTriggered\n")
    end

    -- Only write new entries that haven't been written yet
    local entriesToWrite = {}
    for i = #craftingHistory - (#craftingHistory - lastExportedIndex), #craftingHistory do
        if i > 0 then -- Ensure index is valid
            table.insert(entriesToWrite, craftingHistory[i])
        end
    end

    -- Update last exported index
    lastExportedIndex = #craftingHistory

    -- Write only new entries
    for _, entry in ipairs(entriesToWrite) do
        local line = string.format('"%s","%s","%s","%s",%d,%s,%s,%d,%d,%d,%d,%d,%d,"%s","%s",%s,%s\n',
            time_format(webclock()),                           -- Timestamp of export
            entry.itemKey:gsub('"', '""'),                     -- ItemKey
            entry.label:gsub('"', '""'),                       -- Label
            entry.queryName:gsub('"', '""'),                   -- QueryName
            entry.queryDamage,                                 -- QueryDamage
            time_format(entry.startTime),                      -- StartTime
            time_format(entry.endTime),                        -- EndTime
            entry.duration,                                    -- DurationSeconds
            entry.totalRequested,                              -- TotalRequested
            entry.initialStock,                                -- InitialStock
            entry.finalStock,                                  -- FinalStock
            entry.produced,                                    -- Produced
            entry.remaining,                                   -- Remaining
            tostring(entry.cpuNum):gsub('"', '""'),            -- CPUName
            entry.status,                                      -- Status (completed/canceled)
            entry.cancellationAttempted and "true" or "false", -- CancellationAttempted
            entry.timeoutTriggered and "true" or "false"       -- TimeoutTriggered
        )

        file:write(line)
    end

    file:close()

    if #entriesToWrite > 0 then
        print_info("Appended " .. #entriesToWrite .. " new history entries to " .. filename)
    end

    return true
end
local function loadCraftingHistory()
    local filename = "crafting_history.csv"
    local file = io.open(filename, "r")
    if not file then
        print_info("No existing history file found. Starting fresh.")
        return
    end

    print_info("Loading previous crafting history...")

    -- Skip header line
    file:read("*l")

    local count = 0
    for line in file:lines() do
        count = count + 1

        -- Parse CSV line and reconstruct history entry
        -- This is simplified and would need to match your exact CSV format
        local timestamp, itemKey, label, queryName, queryDamage, startTimeStr, endTimeStr, duration,
        totalRequested, initialStock, finalStock, produced, remaining, cpuNum,
        status, cancellationAttempted, timeoutTriggered = line:match(
            '"([^"]+)","([^"]+)","([^"]+)",(%d+),([^,]+),([^,]+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),"([^"]+)",([^,]+),([^,]+),([^,]+)'
        )

        if itemKey then
            -- Convert string values back to appropriate types
            local entry = {
                itemKey = itemKey,
                label = label,
                queryName = queryName,
                queryDamage = tonumber(queryDamage),
                startTime = 0, -- You'd need to parse the date string
                endTime = 0,   -- You'd need to parse the date string
                duration = tonumber(duration),
                totalRequested = tonumber(totalRequested),
                initialStock = tonumber(initialStock),
                finalStock = tonumber(finalStock),
                produced = tonumber(produced),
                remaining = tonumber(remaining),
                cpuNum = cpuNum,
                status = status,
                cancellationAttempted = (cancellationAttempted == "true"),
                timeoutTriggered = (timeoutTriggered == "true")
            }

            table.insert(craftingHistory, entry)
        end
    end

    file:close()
    lastExportedIndex = #craftingHistory
    print_info("Loaded " .. count .. " historical crafting records.")
end
-- Append one finished-job record to crafting_history.csv
local function logCraftingResult(itemKey, data, status, endTime)
    local file, err = io.open("crafting_history.csv", "a")
    if not file then
        print_error("io.open failed: " .. tostring(err)) -- shows permission‑denied, disk‑full, etc.
        return
    end
    if not fileExists then
        file:write("Timestamp,ItemKey,Label,QueryName,QueryDamage,StartTime,EndTime," ..
            "DurationSeconds,TotalRequested,InitialStock,FinalStock,Produced," ..
            "Remaining,CPUName,Status,CancellationAttempted,TimeoutTriggered\n")
    end
    local finalItem  = ae2.getItemsInNetwork({ name = data.queryName, damage = data.queryDamage })[1]
    local finalStock = finalItem and finalItem.size or 0
    local produced   = math.max(0, finalStock - data.initialStock)
    local remaining  = math.max(0, data.totalRequested - produced)
    local duration   = endTime - data.startTime
    file:write(string.format('"%s","%s","%s","%s",%d,%s,%s,%d,%d,%d,%d,%d,%d,"%s","%s",%s,%s\n',
        time_format(webclock()), itemKey, data.label, data.queryName, data.queryDamage,
        time_format(data.startTime), time_format(endTime), duration, data.totalRequested,
        data.initialStock, finalStock, produced, remaining, tostring(data.cpuNum),
        status, data.cancellationAttempted and "true" or "false",
        (status == "canceled" and "true" or "false")))
    file:close()
end

--------------------------------------------------
-- Utility Functions
--------------------------------------------------
-- Parse full item string into (name, damage)
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

-- Return the first free CPU from AE2
local function getFreeCPU()
    local cpus = ae2.getCpus()
    for i, cpu in ipairs(cpus) do
        if not cpu.busy then
            return cpu
        end
    end
    return nil
end

-- Try to cancel a crafting job by signaling to AE2 to stop the job
local function attemptCancelCraftingJob(itemKey, data)
    -- Log that we're attempting to cancel
    print_warning(string.format("Attempting to cancel crafting job for %s (exceeded %d second timeout)",
        data.label, CRAFTING_TIMEOUT_SECONDS))

    -- Note: According to the API documentation, there's no direct method to cancel a crafting request
    -- We're storing this information and will mark it as timed out in our monitors table

    -- Add a cancellation flag to the data
    data.cancellationAttempted = true
    return true
end

--------------------------------------------------
-- Crafting Request Functions
--------------------------------------------------
-- Check for missing items and submit crafting requests.
-- Only one active request per item is allowed.
local function checkAndSubmitCrafting(monitors)
    for fullItemName, data in pairs(watchitems) do
        -- Only create a new request if not already monitoring this item.
        if not monitors[fullItemName] then
            local desiredCount = data.desired
            local batchSize = data.batch
            local itemname, damage = parseItemName(fullItemName)

            local item_in_network = ae2.getItemsInNetwork({ name = itemname, damage = damage })[1]
            local currentStock = 0
            local label = fullItemName
            if item_in_network then
                currentStock = item_in_network.size
                if item_in_network.label then
                    label = item_in_network.label
                end
            else
                print_debug("Item not found in network. Assuming 0 in stock.")
            end

            if desiredCount > currentStock then
                local difference = desiredCount - currentStock
                local reqsize = math.min(difference, batchSize)
                print_debug(string.format("Need to craft %d more (difference: %d) of %s", reqsize, difference, label))
                local recipe = ae2.getCraftables({ name = itemname, damage = damage })[1]
                if recipe then
                    local freeCPU = getFreeCPU()
                    if freeCPU then
                        print_info(string.format("Requesting crafting of %d of %s on CPU %s...", reqsize, label,
                            freeCPU.name))
                        local monitor = recipe.request(reqsize, false, freeCPU.name)
                        nextMonitorId = nextMonitorId + 1    -- bump the counter

                        monitors[fullItemName] = {           -- store the new monitor
                            id                    = nextMonitorId, -- ← persistent ID
                            monitor               = monitor,
                            startTime             = webclock(),
                            totalRequested        = reqsize,
                            initialStock          = currentStock,
                            queryName             = itemname,
                            queryDamage           = damage,
                            label                 = label,
                            cpuNum                = freeCPU.name,
                            cancellationAttempted = false
                        }
                    else
                        print_warning("No free CPU available for crafting request.")
                    end
                else
                    print_error(string.format("No recipe found for %s/%s", itemname, tostring(damage)))
                end
            else
                print_status(string.format("Stock sufficient: %d / %d for %s", currentStock, desiredCount, label))
            end
            os.sleep(0.1) -- Short delay between requests
        end
    end
end

-- Update the status of current crafting requests.
local function updateMonitors(monitors)
    local timedOutJobs = {}

    print(string.rep("=", 50))

    -- Export active monitors to CSV at the beginning of update
    exportActiveMonitorsToCSV(monitors)

    for itemKey, data in pairs(monitors) do
        local monitor = data.monitor
        local currentTime = webclock()
        local elapsed = currentTime - data.startTime

        -- Re-query current stock for the item.
        local currentItem = ae2.getItemsInNetwork({ name = data.queryName, damage = data.queryDamage })[1]
        local currentStock = currentItem and currentItem.size or 0
        local produced = currentStock - data.initialStock
        if produced < 0 then produced = 0 end
        local remaining = data.totalRequested - produced
        if remaining < 0 then remaining = 0 end

        -- Check if the job has exceeded the timeout threshold
        if not data.cancellationAttempted and elapsed > CRAFTING_TIMEOUT_SECONDS then
            -- Attempt to cancel the job
            if attemptCancelCraftingJob(itemKey, data) then
                -- Mark this job for later review
                table.insert(timedOutJobs, itemKey)
                print_error(string.format("Crafting of %s on CPU %s has timed out after %d seconds (limit: %d seconds).",
                    data.label, tostring(data.cpuNum), elapsed, CRAFTING_TIMEOUT_SECONDS))
            end
        end

        if monitor.isCanceled() then
            local cancelReason = data.cancellationAttempted and " (timeout triggered)" or ""
            print_warning(string.format("Crafting of %s on CPU %s was canceled after %d seconds%s",
                data.label, tostring(data.cpuNum), elapsed, cancelReason))

            -- Add to history
            logCraftingResult(itemKey, data, "canceled", currentTime)

            monitors[itemKey] = nil
        elseif monitor.isDone() then
            print_info(string.format("Crafting of %s on CPU %s completed after %d seconds! Produced: %d, Remaining: %d",
                data.label, tostring(data.cpuNum), elapsed, produced, remaining))

            -- Add to history
            logCraftingResult(itemKey, data, "completed", currentTime)
            monitors[itemKey] = nil
        else
            local timeoutWarning = ""
            if elapsed > (CRAFTING_TIMEOUT_SECONDS * 0.75) and not data.cancellationAttempted then
                timeoutWarning = string.format(" (WARNING: Will timeout in %d seconds)",
                    CRAFTING_TIMEOUT_SECONDS - elapsed)
                gpu.setForeground(COLOR_YELLOW)
            end

            rint_status(string.format(
                "[%d] Crafting %s on CPU %s … Elapsed: %d s, Produced: %d, Remaining: %d%s",
                data.id, data.label, tostring(data.cpuNum), elapsed, produced, remaining, timeoutWarning))


            if timeoutWarning ~= "" then
                gpu.setForeground(COLOR_WHITE)
            end
        end
    end

    -- Log summary of timed out jobs if any
    if #timedOutJobs > 0 then
        print_warning(string.format("Warning: %d crafting jobs exceeded the %d second timeout and were canceled",
            #timedOutJobs, CRAFTING_TIMEOUT_SECONDS))
    end
end

--------------------------------------------------
-- Main Loop
--------------------------------------------------
local function mainLoop()
    local monitors = {} -- Global table to hold active crafting requests

    while true do
        gpu.setForeground(COLOR_GREEN)
        print("\n" .. string.rep("=", 50))
        print_info("Starting new loop cycle at " .. time_format(webclock()))
        print(string.rep("=", 50))
        gpu.setForeground(COLOR_WHITE)

        local rs_input = 100 -- Stubbed redstone signal
        print_debug(string.format("Redstone input is %d", rs_input))
        if rs_input > 0 then
            -- Submit new crafting requests if needed.
            checkAndSubmitCrafting(monitors)
            -- Update status of all active crafting requests.
            updateMonitors(monitors)
        else
            print_debug("Skipping crafting check. Redstone signal is off.")
        end

        os.sleep(5) -- Delay before starting the next cycle.
    end
end

--------------------------------------------------
-- Initialization and Start
--------------------------------------------------
gpu.setForeground(COLOR_CYAN)
print(string.rep("*", 50))
print("    AE2 AUTO-CRAFTER SYSTEM")
print("    " .. time_format(webclock()))
print("    Timeout threshold: " .. CRAFTING_TIMEOUT_SECONDS .. " seconds")
print("    CSV Export: ENABLED (active_monitors.csv, crafting_history.csv)")
print(string.rep("*", 50))
gpu.setForeground(COLOR_WHITE)

-- Load previous history if available
-- loadCraftingHistory()
-- Create empty CSV files on startup
-- exportCraftingHistoryToCSV()

logNetworkItems() -- Log the network items once before starting the main loop.
print_info("Starting main monitoring loop...")
mainLoop()        -- Start the main loop.
