local w = require "lib"
local d = require "luadash"

local conf = w.load_config({
    "network_name"
})

local function split_at_spaces(s)
    local t = {}
    for i in string.gmatch(s, "%S+") do
       table.insert(t, i)
    end
    return t
end

local function first_letter(s)
    return string.sub(s, 1, 1)
end

local usage = [[
Welcome to the Wyvern CLI Client, "Because Gollark Was Lazy".
All commands listed below can also be accessed using single-letter shortcuts for convenience.

withdraw [quantity] [name] - withdraw [quantity] items with display names close to [name] from storage
withdraw [items] - as above but withdraws all available matching items
]]

local commands = {
    help = function() return usage end,
    withdraw = function(number, ...)
        local query_tokens = {...}
        local quantity = math.huge
        if tonumber(number) ~= nil then 
            quantity = tonumber(number)
        else
            table.insert(query_tokens, 1, numbr)
        end
        local query = table.concat(query_tokens, " ") -- unsplit query

        local items = w.query_by_type("storage", {
            type = "search",
            query = query
        })
    end
}

w.init()

if not turtle then error "Wyvern CLI must be run on a turtle." end

print "Wyvern CLI Client"

while true do
    write "|> "
    local text = read()
    local tokens = split_at_spaces(text)
    local command = tokens[1]
    local args = d.tail(tokens)
    local fn = commands[command]
    if not fn then
        for command_name, func in pairs(commands) do
            if first_letter(command_name) == first_letter(command) then fn = func end
        end
    end
    if not fn then
        print("Command", command, "not found.")
    end

    local ok, result = pcall(fn(table.unpack(args)))
    if result then textutils.pagedPrint(result) end
end