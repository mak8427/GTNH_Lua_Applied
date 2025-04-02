local internet = require("internet")
local component = require("component")
local filesystem = require("filesystem")

local me
if component.isAvailable("me_controller") then
    me = component.me_controller
elseif component.isAvailable("me_interface") then
    me = component.me_interface
else
    print("You need to connect the adapter to either a me controller or a me interface")
    os.exit()
end

function webclock()
    local handle = internet.request("http://www.rootdir.org/webclock.php?tz=Europe/Rome&locale=pt_BR.UTF-8")
    local result = ""

    for chunk in handle do result = chunk end

    local datetime = os.time({year=result:sub(1,4), month=result:sub(6,7), day=result:sub(9,10), hour=result:sub(12,13), min=result:sub(15,16), sec=result:sub(18,19)})

    return datetime
end

function time_format(datetime)
    local time_format = os.date("%Y-%m-%d %H:%M:%S", datetime)
    return time_format
end

function AE_get_items(datetime)
    local raw = ""
    local isModpackGTNH, storedItems = pcall(me.allItems)

    local time_format = time_format(datetime)
    local count = 1

    if not isModpackGTNH then
        for item in storedItems do
            if type(item) == 'table' then
                string = string .. "," .. '{"item":"' .. item['label'] .. '","quantity":"' .. item["size"] .. '","datetime":"'.. time_format .. '"}' .. "\n"
                count = count + 1
            end
        end
        return string
    else
        for k, v in pairs(me.getItemsInNetwork()) do
            if type(v) == 'table' and v["size"] and v["size"] > 10 then
                if v["label"] and string.find(v["label"], ",") then
                    v["label"] = string.gsub(v["label"], ",", "-")
                end
                raw = raw .. v["label"] .. ',' .. v["size"] .. ',' .. time_format .. "\n"
                count = count + 1
            end
        end
    end
    print("Items Crawled: " .. count)
    return raw
end

function sleep(n)
    os.execute("sleep " .. tonumber(n))
end

function acquireLock(lockFile, maxAttempts)
    local attempts = 0
    while attempts < maxAttempts do
        -- Check if the lock file exists
        if not filesystem.exists(lockFile) then
            -- Try to create the lock file
            local file = io.open(lockFile, "w")
            if file then
                -- Write a timestamp and process info to the lock file
                file:write(os.date("%Y-%m-%d %H:%M:%S"))
                file:close()
                return true
            end
        end

        -- If we're here, either the file exists or we couldn't create it
        -- Check if the lock is stale (optional, if you have access to process info)
        if filesystem.exists(lockFile) then
            local info = filesystem.lastModified(lockFile)
            -- If lock is older than 10 minutes, assume it's stale and remove it
            if info and os.time() - info > 600 then
                print("Removing stale lock file")
                filesystem.remove(lockFile)
                -- Don't increment attempts, try again immediately
                sleep(0.5)
                goto continue
            end
        end

        -- Wait and retry
        sleep(1)
        attempts = attempts + 1
        print("Waiting for File lock, attempt " .. attempts .. "/" .. maxAttempts)

        ::continue::
    end

    print("Failed to acquire lock after " .. maxAttempts .. " attempts")
    return false
end

function releaseLock(lockFile)
    if filesystem.exists(lockFile) then
        local success, err = filesystem.remove(lockFile)
        if not success then
            print("Warning: Failed to remove lock file: " .. (err or "unknown error"))
        end
    end
end

check_time = 1
datetime = webclock()
local file = io.open("Export.csv", "a")
local lockFile = "file.lock"

repeat
    -- Try to acquire the lock
    if acquireLock(lockFile, 10) then
        local success, err = pcall(function()
            if check_time >= 5 then
                print("Updating Web Time")
                datetime = webclock()
                check_time = 1
            end

            local items = AE_get_items(datetime)
            file:write(items)
            file:flush()

            print("Getting Items! " .. time_format(datetime))
        end)

        -- Always release the lock, even if an error occurred
        releaseLock(lockFile)

        if not success then
            print("Error occurred: " .. tostring(err))
        end
    else
        print("Skipping this iteration due to lock acquisition failure")
    end

    -- Wait 5 minutes for another update
    sleep(300)

    datetime = datetime + 300
    check_time = check_time + 1

until 1 > 5
file:close()