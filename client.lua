local w = require "lib"
local d = require "luadash"

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
]]

local commands = {
    help = function() print(usage) end
}


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

    fn(table.unpack(args))
end