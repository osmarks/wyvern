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
withdraw [items] - as above but withdraws all available matching items
dump [slot] - dump stack in slot back to storage
dump - dump whole inventory to storage
craft - runs turtle.craft
reindex - force storage server to reindex its contents]]

local function dump(slot)
    return w.query_by_type("storage", {
        type = "insert",
        from_slot = slot,
        from_inventory = conf.network_name
    })
end

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
        local exact = false

        local query_match = string.match(query, "!(.*)")
        if query_match ~= nil then query = query_match exact = true end

        local items = w.unwrap(w.query_by_type("storage", {
            type = "search",
            query = query
        }), "searching for items")

        for _, item_type in pairs(items) do
            while quantity > 0 and item_type.count > 0 do
                local max_quantity
                if quantity < 64 then max_quantity = quantity end
                local moved = w.unwrap(w.query_by_type("storage", {
                    type = "extract",
                    ID = item_type.ID,
                    meta = item_type.meta,
                    NBT_hash = item_type.NBT_hash,
                    quantity = max_quantity,
                    destination_inventory = conf.network_name,
                    exact = exact
                }), "extracting a stack").moved
                if moved == 0 then -- inventory full
                    quantity = 0
                end
                quantity = quantity - moved
                item_type.count = item_type.count - moved
            end
        end
    end,
    dump = function(slot)
        local slot = tonumber(slot)
        if not slot then
            for i = 1, 16 do
                w.unwrap(dump(i), "dumping inventory")
            end
        else
            w.unwrap(dump(slot), "dumping slot " .. tostring(slot))
        end
    end,
    craft = function()
        local result = turtle.craft()
        if not result then return "Invalid or no recipe." end
    end,
    reindex = function()
        w.unwrap(w.query_by_type("storage", { type = "reindex" }), "requesting reindexing")
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