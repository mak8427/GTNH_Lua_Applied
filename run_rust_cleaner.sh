#!/bin/bash

# Change to the correct working directory
cd /mnt/sdb/gtnh_ger/World/opencomputers/f93bf4e7-03b1-41e8-893e-d9033d3f97a9/home/GTNH_Lua_Applied || exit 1

# Log the start time and environment for debugging
echo "Script started at $(date)" >> /mnt/sdb/gtnh_ger/World/opencomputers/f93bf4e7-03b1-41e8-893e-d9033d3f97a9/home/GTNH_Lua_Applied/Rust_cleaner.log
echo "PATH=$PATH" >> /mnt/sdb/gtnh_ger/World/opencomputers/f93bf4e7-03b1-41e8-893e-d9033d3f97a9/home/GTNH_Lua_Applied/Rust_cleaner.log

# Run the Rust binary and capture both stdout and stderr
/mnt/sdb/gtnh_ger/World/opencomputers/f93bf4e7-03b1-41e8-893e-d9033d3f97a9/home/GTNH_Lua_Applied/Cleaner >> /mnt/sdb/gtnh_ger/World/opencomputers/f93bf4e7-03b1-41e8-893e-d9033d3f97a9/home/GTNH_Lua_Applied/Rust_cleaner.log 2>&1
