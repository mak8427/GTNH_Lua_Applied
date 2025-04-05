---
--- Created by mak.
--- DateTime: 05/04/25 20.59
---
function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end


function lock_start()
    local lock = "file.lock"
    if file_exists(lock) == false then
        local file = io.open(lock, "w")
        file.close()
        return false
    end
    return true
end


function lock_end()
    local lock = "/file.lock"
    os.remove(lock)
end

local done = false

while done == false do
    if lock_start() then
        print("stack")
        done = true
    end
end
lock_end()
