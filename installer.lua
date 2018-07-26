local d = require "luadash" or _

local wyvern_files = {
    root = "https://osmarks.tk/git/osmarks/wyvern/raw/branch/master/",
    files = { "installer.lua", "luadash.lua", "lib.lua" }
}

local args = {...}
local command = args[1] -- native luadash head is broken
local params = d.tail(args)

local function download_group(g)
    d.map(g.files, function(file) 
        local url = g.root .. file
        local h = http.get(url)
        local contents = h.readAll()
        local f = fs.open(file, "w")
        f.write(contents)
        f.close()
        print("Written", file, "from", url)
    end)
end

local function prompt(msg)
    write(msg .. "> ")
    return read()
end

local function install_wyvern() download_group(wyvern_files) end
if command == "update" then
    install_wyvern()
elseif command == "install" then
    install_wyvern()
    shell.run "edit wyvern_config.tbl" -- open editor for config edits
end