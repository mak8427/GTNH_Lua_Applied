local internet = require("internet")
local component = require("component")
local me

if component.isAvailable("me_controller") then
    me = component.me_controller
    print(me)
elseif component.isAvailable("me_interface") then
    me = component.me_interface
else
    print("You need to connect the adapter to either a me controller or a me interface")
    os.exit()
end

            -- Function to get Real World time
function webclock()
print("[DEBUG] Requesting web clock...")
local handle = internet.request("http://www.rootdir.org/webclock.php?tz=America/Bahia&locale=pt_BR.UTF-8")
local result = ""
for chunk in handle do
    result = result .. chunk
    end
    print("[DEBUG] Raw webclock result: " .. result)
    if #result < 19 then
        print("[DEBUG] Webclock returned an unexpected result: " .. result)
        return os.time()  -- Fallback to local time
        end
    local datetime = os.time({
        year  = tonumber(result:sub(1,4)),
                             month = tonumber(result:sub(6,7)),
                             day   = tonumber(result:sub(9,10)),
                             hour  = tonumber(result:sub(12,13)),
                             min   = tonumber(result:sub(15,16)),
                             sec   = tonumber(result:sub(18,19))
    })
    print("[DEBUG] Parsed web clock time: " .. time_format(datetime))
    return datetime
    end

function time_format(datetime)
return os.date("%Y-%m-%d %H:%M:%S", datetime)
end

-- Updated function to get the items from AE2 as JSON-formatted lines
function AE_get_items(datetime)
local output = ""
local formatted_time = time_format(datetime)
local count = 0

local success, storedItems = pcall(me.allItems)
if success and type(storedItems) == "table" then
    print("[DEBUG] Using GTNH method to retrieve items.")
    print(storedItems)
    for i, item in ipairs(storedItems) do
        if type(item) == "table" then
            output = output .. '{"item":"' .. item.label .. '","quantity":"' .. item.size .. '","datetime":"' .. formatted_time .. '"}' .. "\n"
            count = count + 1
        end
    end
else
    print("[DEBUG] Using standard method to retrieve items.")
    local items = me.getItemsInNetwork()
    if type(items) == "table" then
        for k, item in pairs(items) do
            if type(item) == "table" then
                output = output .. '{"item":"' .. item.label .. '","quantity":"' .. item.size .. '","datetime":"' .. formatted_time .. '"}' .. "\n"
                count = count + 1
            end
        end
    end
end

print("[DEBUG] Retrieved " .. count .. " item(s) at " .. formatted_time)
return output
end

function sleep(n)
os.execute("sleep " .. tonumber(n))
end

-- Check if Items.csv exists. If not, create it and add header and four tilde lines.
local filename = "Items.csv"
print("[DEBUG] Checking for file: " .. filename)
local file = io.open(filename, "r")
if not file then
    print("[DEBUG] File not found. Creating new file: " .. filename)
    file = io.open(filename, "w")
    if file then
        file:write("Item,Quantity,DateTime\n")
        file:close()
        print("[DEBUG] Created file and wrote header with tildes.")
        else
            print("[DEBUG] Error: Could not create file " .. filename)
            os.exit()
            end
            else
                print("[DEBUG] File exists: " .. filename)
                file:close()
                end

                local i = 1
                local check_time = 1
                local datetime = webclock()

                repeat
                print("[DEBUG] Cycle " .. i .. " at time " .. time_format(datetime))
                if check_time >= 5 then
                    print("[DEBUG] Updating web clock time...")
                    datetime = webclock()
                    check_time = 1
                    end

                    local items = AE_get_items(datetime)
                    local file = io.open(filename, "a")
                    if file then
                        file:write(items)
                        file:close()
                        print("[DEBUG] Written items to " .. filename .. " at " .. time_format(datetime))
                        else
                            print("[DEBUG] Error: Unable to open file " .. filename .. " for appending.")
                            end

                            sleep(60)  -- Wait 60 seconds for next update
                            datetime = datetime + 60
                            check_time = check_time + 1
                            i = i + 1
                            until i > 5
