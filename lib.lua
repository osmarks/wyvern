--[[
Wyvern utility/API library
Contains:
error handling (a set of usable errors and human-readable printing for them),
networking (a simple node-based system on top of rednet)
configuration (basically just loading serialized tables from a file)
general functions of utility
Plethora helpers
]]

local d = require "luadash"

-- ERRORS

local errors = {
    INTERNAL = 0, -- Internal error data can be in any format or not exist
    INVALID = 1, -- Invalid message errors don't require data at all
    NOPATTERN = 2, -- No pattern errors should contain a human-readable pattern name in their data
    NOITEMS = 3, -- No item errors should either provide a table of { type = "human-readable name if available or internal ID if not", quantity = number of items missing } or a human-readable string
    NORESPONSE = 4, -- No response errors (should only be produced by query_ functions may contain a description of which node the error is caused by in their data
    NOMATCHINGNODE = 5, -- No matching node errors (should only be prodcuced by query_ functions) may contain a description of which type of node cannot be found.
    NOSPACE = 6, -- No data required. Should be returned if there is no available storage space.
    make = function(e, d)
        return { type = "error", error = e, data = d }
    end
}

-- Converts an error into human-readable format
errors.format = function(e)
    if type(e) == "string" then return e end
    if not (e.type and e.type == "error" and e.data and e.error) then return "Provided error is not an error object." end
    if e.error == errors.INTERNAL then
        return "Internal error - provided info: " .. textutils.serialise(e.data) .. "."
    elseif e.error == errors.INVALID then
        return "Request invalid."
    elseif e.error == errors.NOPATTERN then
        return "Missing pattern " .. textutils.serialise(e.data) .. "."
    elseif e.error == errors.NOITEMS then
        local thing_missing = "???"
        if type(e.data) == "table" and e.data.type and e.data.quantity then
            thing_missing = tostring(e.data.quantity) .. " " .. e.data.type
        elseif type(e.data) == "string" then
            thing_missing = e.data
        end

        return "Missing " .. thing_missing .. " to fulfil request."
    elseif e.error == errors.NORESPONSE then
        local text = "No response"
        if e.data then text = text .. " from " .. textutils.serialise(e.data) end
        return text .. "."
    elseif e.error == errors.NOMATCHINGNODE then
        if e.data then
            return "No " .. textutils.serialise(e.data) .. " node found."
        else
            return "No node of desired type found."
        end
    elseif e.error == errors.NOSPACE then
        return "No available storage space."
    else
        return "Error is invalid. Someone broke it."
    end
end

-- NETWORKING

local protocol = "wyvern"

local lookup_cache = {}

local function cached_lookup(protocol)
    if lookup_cache[protocol] then return lookup_cache[protocol]
    else 
        local ID = rednet.lookup(protocol)
        lookup_cache[protocol] = ID
        return ID
    end
end

local function init_screen(scr, bg, fg)
    scr.setCursorPos(1, 1)
    scr.setBackgroundColor(bg)
    scr.setTextColor(fg)
    scr.clear()
end

-- Runs a Wyvern node server.
-- First argument is a function to be run for requests. It will be provided the request data and must return the value to respond with.
-- If it errors, an internal error will be returned.
-- Second argument is the type of node to host as. Other nodes may attempt to use this to discover other local-network nodes.
-- Also displays a nice informational UI
local function serve(fn, node_type)
    local w, h = term.getSize()
    local titlebar = window.create(term.current(), 1, 1, w, 1)
    local main_screen = window.create(term.current(), 1, 2, w, h - 1)

    init_screen(titlebar, colors.lightGray, colors.black)
    titlebar.write("Wyvern " .. node_type)

    init_screen(main_screen, colors.white, colors.black)
    term.redirect(main_screen)

    titlebar.redraw()
    main_screen.redraw()

    rednet.host(protocol .. "/" .. node_type, node_type .. "/" .. tostring(os.getComputerID()))

    while true do
        local sender, message = rednet.receive(protocol)

        -- As a default response, send an "invalid request" error
        local response = errors.make(errors.INVALID)

        local start_time = os.clock()
        print(tostring(sender) .. " > " .. tostring(os.getComputerID())) -- show sender and recipient

        -- If the message actually is a compliant Wyvern request (is a table, containing a message ID, request, and a type saying "request") then run
        -- the provided server function, and package successful results into a response type
        if type(message) == "table" and message.type and message.type == "request" and message.request then
            print("Request:", textutils.serialise(message.request))

            local ok, result = pcall(fn, message.request)
            if not ok then 
                if type(result) ~= "table" or not result.error then response = errors.make(errors.INTERNAL, result)
                else response = result end
                print("Error:", textutils.serialise(result)) -- show error
            else 
                local end_time = os.clock()
                print("Response:", textutils.serialise(result))
                print("Time:", string.format("%.1f", end_time - start_time))
                response = { type = "OK", value = result }
            end
        else
            print("Request Invalid")
        end

        main_screen.redraw()

        rednet.send(sender, response, protocol)
    end
end

-- Attempts to send "request" to "ID", with the maximum number of allowable tries being "tries"
local function query_by_ID(ID, request, max_tries)
    local max_tries = max_tries or 3
    local request_object = { type = "request", request = request }
    local result = nil
    local tries = 0

    repeat
        rednet.send(ID, request_object, protocol)
        _, result = rednet.receive(protocol, 1)
        tries = tries + 1
    until result ~= nil or tries >= max_tries

    if result == nil then result = errors.make(errors.NORESPONSE, ID) end

    return result
end

local function query_by_type(type, request, tries)
    local ID = cached_lookup(protocol .. "/" .. type)
    if not ID then return errors.make(errors.NOMATCHINGNODE, type) end
    return query_by_ID(ID, request, tries)
end

-- PLETHORA HELPERS

-- Converts a plethora item (as in a slot) to a Wyvern item
local function to_wyvern_item(item)
    return { NBT_hash = item.NBT_hash or item.nbtHash, ID = item.ID or item.name, meta = item.meta or item.damage, display_name = item.display_name or item.displayName, count = item.count }
end

-- Gets the internal identifier of an item - unique (hopefully) per type of item, as defined by NBT, metadata/damage and ID/name
local function get_internal_identifier(item)
    local n = item.ID
    if item.meta then n = n .. ":" .. item.meta end
    if item.NBT_hash then n = n .. "#" .. item.NBT_hash end
    return n
end

-- Inverse of get_internal_identifier - parses that kind of string into ID/meta/NBT
local function string_to_item(s)
    local mod, item, meta, NBT = string.match(s, "([A-Za-z0-9_]+):([A-Za-z0-9_]+):([0-9]+)#([0-9a-f]+)")
    if not NBT then mod, item, meta = string.match(s, "([A-Za-z0-9_]+):([A-Za-z0-9_]+):([0-9]+)") end
    if not mod or not item or not meta then error(errors.make(errors.INTERNAL, "string did not match regex")) end
    return { ID = mod .. ":" .. item, meta = tonumber(meta), NBT = NBT }
end

-- GENERAL STUFF

-- Converts a table of the form {"x", "x", "y"} into {x = 2, y = 1}
local function collate(items)
    local ret = {}
    for _, i in pairs(items) do
        ret[i] = (ret[i] or 0) + 1
    end
    return ret
end

-- Functions like "collate" but on itemstacks (adds their counts)
local function collate_stacks(s)
    local out = {}
    for _, stack in pairs(s) do
        local i = get_internal_identifier(stack)
        if out[i] then out[i].count = out[i].count + stack.count
        else out[i] = stack end
    end
    return out
end

-- Checks whether "needs"'s (a collate-formatted table) values are all greater than those of "has"
local function satisfied(needs, has)
    local good = true
    for k, qty in pairs(needs) do
        if qty > (has[k] or 0) then good = false end
    end
    return good
end

-- Loads a config file (in serialized-table format) from "filename" or wyvern_config.tbl
-- "required_data" is a list of keys which must be in the config file's data
-- "defaults" is a map of keys and default values for them, which will be used if there is no matching key in the data
local function load_config(required_data, defaults, filename)
    local required_data = required_data or {}
    local defaults = defaults or {}

    local filename = filename or "wyvern_config.tbl"
    local f = fs.open(filename, "r")
    local data = textutils.unserialise(f.readAll())
    f.close()

    for k, required_key in pairs(required_data) do
        if not data[required_key] then
            if defaults[required_key] then data[required_key] = defaults[required_key]
            else error({"Missing config key!", required_key, data}) end
        end
    end

    return data
end

-- Returns a list of peripheral objects whose type, name and object satisfy the given predicate
local function find_peripherals(predicate, from)
    local matching = {}
    local list
    if from then
        list = peripheral.call(from, "getNamesRemote")
    else
        list = peripheral.getNames()
    end
    for k, name in pairs(list) do
        local wrapped = peripheral.wrap(name)
        local type = peripheral.getType(name)
        if predicate(type, name, wrapped) then table.insert(matching, { wrapped = wrapped, name = name} ) end
    end
    return matching
end

-- Set up stuff for running this library's features (currently, modem initialization)
local function init()
    d.map(find_peripherals(function(type, name, wrapped) return type == "modem" end), function(p) rednet.open(p.name) end)
end

-- Rust-style unwrap. If x is an OK table, will take out its contents and return them - if error, will crash and print it, with msg if provided
local function unwrap(x, msg, ignore)
    if not x or type(x) ~= "table" or not x.type then x = errors.make(errors.INTERNAL, "Error/response object is invalid. This is probably a problem with the node being contacted.") end

    if x.type == "error" then
        if ignore then
            for _, etype in pairs(ignore) do
                if x.error == etype then
                    return
                end
            end
        end

        local text = "An error occured"
        if msg then text = text .. " " .. msg
        else text = text .. "!" end
        text = text .. ".\nDetails: " .. errors.format(x)
        error(text)
    elseif x.type == "OK" then
        return x.value
    end
end

-- Wrap x in an OK result
local function make_OK(x)
    return { type = "OK", value = x }
end

-- Shallow-merge t2 into t1 in-place
local function join(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
end

-- TODO: Not do this
return { errors = errors, serve = serve, query_by_ID = query_by_ID, query_by_type = query_by_type, unwrap = unwrap, to_wyvern_item = to_wyvern_item, get_internal_identifier = get_internal_identifier, load_config = load_config, find_peripherals = find_peripherals, init = init, collate = collate, satisfied = satisfied, collate_stacks = collate_stacks, make_error = errors.make, make_OK = make_OK, string_to_item = string_to_item, join = join }