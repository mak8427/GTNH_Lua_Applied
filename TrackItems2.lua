local internet = require("internet")
local component = require("component")

local me
if component.isAvailable("me_controller") then
    me = component.me_controller
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

                local datetime = os.time({
                    year  = result:sub(1,4),
                                         month = result:sub(6,7),
                                         day   = result:sub(9,10),
                                         hour  = result:sub(12,13),
                                         min   = result:sub(15,16),
                                         sec   = result:sub(18,19)
                })
                print("[DEBUG] Parsed web clock time: " .. time_format(datetime))
                return datetime
                end

                -- Function to format the date/time
                function time_format(datetime)
                local formatted = os.date("%Y-%m-%d %H:%M:%S", datetime)
                return formatted
                end

                -- Function to get the items from AE2 with debugging output
                function AE_get_items(datetime)
                local output = ""
                local formatted_time = time_format(datetime)
                print("[DEBUG] AE_get_items called with time: " .. formatted_time)

                local isModpackGTNH, storedItems = pcall(me.allItems) -- tries the allItems method only available on the GTNH modpack.
                local count = 0

                if isModpackGTNH then
                    print("[DEBUG] Using GTNH method to retrieve items.")
                    -- Using ipairs for a proper table iteration
                    for _, item in ipairs(storedItems) do
                        if type(item) == 'table' then
                            output = output .. "," .. '{"item":"' .. item['label'] .. '","quantity":"' .. item["size"] .. '","datetime":"' .. formatted_time .. '"}' .. "\n"
                            count = count + 1
                            end
                            end
                            else
                                print("[DEBUG] Using standard method to retrieve items.")
                                local items = me.getItemsInNetwork()
                                for k, v in pairs(items) do
                                    if type(v) == 'table' then
                                        output = output .. "," .. '{"item":"' .. v['label'] .. '","quantity":"' .. v["size"] .. '","datetime":"' .. formatted_time .. '"}' .. "\n"
                                        count = count + 1
                                        end
                                        end
                                        end

                                        print("[DEBUG] AE_get_items retrieved " .. count .. " item(s) at " .. formatted_time)
                                        return output
                                        end

                                        function sleep(n)
                                        os.execute("sleep " .. tonumber(n))
                                        end

                                        -- Main loop variables
                                        local i = 1
                                        local check_time = 1
                                        local datetime = webclock()

                                        repeat
                                        print("[DEBUG] Cycle " .. i .. " starting at " .. time_format(datetime))

                                        -- Update the internal timer with the Webclock time every 5 cycles
                                        if check_time >= 5 then
                                            print("[DEBUG] Updating Web Time")
                                            datetime = webclock()
                                            check_time = 1
                                            end

                                            local file = io.open("Items.txt", "a")
                                            if not file then
                                                print("[DEBUG] Error: Unable to open Items.txt for appending.")
                                                else
                                                    local items = AE_get_items(datetime)
                                                    file:write(items)
                                                    file:close()
                                                    print("[DEBUG] Written items to Items.txt at " .. time_format(datetime))
                                                    end

                                                    print("Getting Items! " .. time_format(datetime))

                                                    -- Wait 60 seconds for another update (adjust this value if needed)
                                                    sleep(60)

                                                    datetime = datetime + 60
                                                    check_time = check_time + 1
                                                    i = i + 1
                                                    until i > 5
