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
    if not (e.type and e.type == "error" and e.data and e.error) then return "Provided error is not an error object." end
    if e.error == errors.INTERNAL then
        return "Internal error - provided info: " .. textutils.serialise(e.data) .. "."
    elseif e.error == errors.INVALID then
        return "Request invalid."
    elseif e.errors == errors.NOPATTERN then
        return "Missing pattern " .. textutils.serialise(e.data) .. "."
    elseif e.errors == errors.NOITEMS then
        local thing_missing = "???"
        if type(e.data) == "table" and e.data.type and e.data.quantity then
            thing_missing = tostring(e.data.quantity) .. " " .. e.data.type
        elseif type(e.data) == "string" then
            thing_missing = e.data
        end

        return "Missing " .. thing_missing .. " to fulfil request."
    elseif e.errors == errors.NORESPONSE then
        local text = "No response"
        if e.data then text = text .. " from " .. textutils.serialise(e.data) end
        return text .. "."
    elseif e.errors == errors.NOMATCHINGNODE then
        if e.data then
            return "No " .. textutils.serialise(e.data) .. " node found."
        else
            return "No node of desired type found."
        end
    elseif e.errors == errors.NOSPACE then
        return "No available storage space."
    else
        return "Error is invalid. Someone broke it."
    end
end

-- NETWORKING

local protocol = "wyvern"

-- Runs a Wyvern node server.
-- First argument is a function to be run for requests. It will be provided the request data and must return the value to respond with.
-- If it errors, an internal error will be returned.
-- Second argument is the type of node to host as. Other nodes may attempt to use this to discover other local-network nodes.
local function serve(fn, nodeType)
    rednet.host(protocol .. "/" .. nodeType, nodeType .. "/" .. tostring(os.getComputerID()))

    while true do
        local sender, message = rednet.receive(protocol)

        -- As a default response, send an "invalid request" error
        local response = errors.make(errors.INVALID)

        -- If the message actually is a compliant Wyvern request (is a table, containing a message ID, request, and a type saying "request") then run
        -- the provided server function, and package successful results into a response type
        if type(message) == "table" and message.type and message.type == "request" and message.request then
            local ok, result = pcall(fn, request)
            if not ok then response = errors.make(errors.INTERNAL, result) end
            else response = { type = "response", response = result }
        end

        rednet.send(sender, response, protocol)
    end
end

-- Attempts to send "request" to "ID", with the maximum number of allowable tries being "tries"
local function query_by_ID(ID, request, tries)
    local max_tries = tries or 3
    local request_object = { type = "request", request = request }
    local result, tries

    repeat
        rednet.send(id, request_object, protocol)
        _, result = rednet.receive(protocol, 1)
        sleep(1)
    until result ~= nil or tries >= max_tries

    if result == nil then result = errors.make(errors.NORESPONSE, ID) end

    return result
end

local function query_by_type(type, request, tries)
    local ID = rednet.lookup(protocol .. "/" .. type)
    if not ID then return errors.make(errors.NOMATCHINGNODE, type) end
    return query_by_ID(ID, request, tries)
end

-- PLETHORA HELPERS

-- Gets the internal identifier of an item - unique (hopefully) per type of item, as defined by NBT, metadata/damage and ID/name
local function get_internal_identifier(item)
    local n = item.name .. ":" .. item.damage
    if item.nbtHash then n = n .. "#" .. item.nbtHash end
    return n
end

-- GENERAL STUFF

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
local function find_peripherals(predicate)
    local matching = {}
    for k, name in pairs(peripheral.getNames()) do
        local wrapped = peripheral.wrap(name)
        local type = peripheral.getType(name)
        if predicate(type, name, wrapped) then table.insert(matching, wrapped) end
    end
    return matching
end

-- Set up stuff for running this library's features (currently, modem initialization)
local function init()
    d.map(find_peripherals(function(type, name, wrapped) return type == "modem" end), rednet.open)
end

return { errors = errors, serve = serve, query_by_ID = query_by_ID, query_by_type = query_by_type, load_config = load_config, find_peripherals = find_peripherals, init = init }