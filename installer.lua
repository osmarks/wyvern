local d = _ or require "luadash"

local wyvern_files = {
    root = "https://osmarks.tk/git/osmarks/wyvern/raw/branch/master/",
    files = { "installer.lua", "luadash.lua", "lib.lua" }
}

local ccfuse_files = {
    root = "https://raw.githubusercontent.com/apemanzilla/ccfuse/master/client/",
    files = { "base64.lua", "json.lua", "ccfuse.lua" }
}

local args = {...}
local command = d.head(args)
local params = d.tail(args)

local function download_files(urls)
    d.map(urls, function(urls) shell.run("wget", url) end) -- TODO: stop using wget and use actual HTTP/FS API
end

local function download_group(g)
    download_files(d.map(g.files, function(file) return g.root .. file end))
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