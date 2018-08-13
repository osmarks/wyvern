local w = require "lib"
local d = require "luadash"
local readline = require "readline"

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

local usage = 
[[Welcome to the Wyvern CLI Client, "Because Gollark Was Lazy".
All commands listed below can also be accessed using single-letter shortcuts for convenience.

withdraw [quantity] [name] - withdraw [quantity] items with display names close to [name] from storage
withdraw [items] - as above but withdraws all available matching items]]

local commands = {
    help = function() return usage end,
    withdraw = function(number, ...)
        local query_tokens = {...}
        local quantity = math.huge
        if tonumber(number) ~= nil then 
            quantity = tonumber(number)
        else
            table.insert(query_tokens, 1, number)
        end
        local query = table.concat(query_tokens, " ") -- unsplit query

        local items = unwrap(w.query_by_type("storage", {
            type = "search",
            query = query
        }), "searching for items")

        for _, item_type in pairs(items) do
            do
                local max_quantity
                if quantity < 64 then max_quantity = quantity end
                local moved = unwrap(w.query_by_type("storage", {
                    type = "extract",
                    ID = item_type.ID,
                    meta = item_type.meta,
                    NBT_hash = item_type.NBT_hash,
                    quantity = max_quantity,
                    destination_inventory = conf.network_name
                }), "extracting a stack").moved
                quantity = quantity - moved
                item_type.count = item_type.count - moved
            until quantity == 0 or item_type.count == 0
        end

        if quantity == 0 then break end
    end
}

w.init()

if not turtle then error "Wyvern CLI must be run on a turtle." end

print "Wyvern CLI Client"

local history = {}

while true do
    write "|> "
    local text = readline(nil, history)

    if text ~= "" then table.insert(history, text) end

    local tokens = split_at_spaces(text)

    local command = tokens[1]
    local args = d.tail(tokens)
    local fn = commands[command]
    if not fn then
        for command_name, func in pairs(commands) do
            if command and first_letter(command_name) == first_letter(command) then fn = func end
        end
    end
    if not fn then
        print("Command", command, "not found.")
    else
        local ok, result = pcall(fn, table.unpack(args))
        if result then textutils.pagedPrint(result) end
    end
end