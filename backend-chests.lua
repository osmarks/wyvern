-- Chest backend
-- Currently just the one for Dragon. Will not actually work yet.

local w = require "lib"
local d = require "luadash"

local conf = w.load_config({
    "buffer_internal",
    "buffer_external"
})

local BUFFER_OUT_SLOT = 1
local BUFFER_IN_SLOT = 2

-- Find all chests or shulker boxes
local inventories = d.map_with_key(w.find_peripherals(function(type, name, wrapped)
    return string.find(name, "chest") or string.find(name, "shulker")
end), function(_, p) return p.name, p.wrapped end)

local display_name_cache = {}

-- Gets the display name of the given item (in the given chest peripheral & slot)
-- If its name is not cached, cache it.
-- If it is, just return the cached name
local function cache(item, chest, slot)
    local idx = w.get_internal_identifier(item)
    
    if display_name_cache[idx] then
        return display_name_cache[idx]
    else
		local n = chest.getItemMeta(slot).displayName
        display_name_cache[idx] = n
		return n
    end
end

local index = {}
-- Update the index for the given peripheral
local function update_index_for(name)
    local inv = inventories[name]
    local data = inv.list()
    
    for slot, item in pairs(data) do
        data[slot].display_name = cache(item, inv, slot)
    end
    
    index[name] = data
end

-- Reindex all connected inventories
local function update_index()
    print "Indexing started."
	for n in pairs(inventories) do
		update_index_for(n)
		sleep()
	end
	print "Indexing complete."
end

-- Finds all items matching a certain predicate.
-- Returns a table of tables of { name, slot, item }
local function find(predicate)
    local ret = {}
    for inventory, items in pairs(index) do
        for slot, item in pairs(items) do
            local ok, extra = predicate(item) -- allow predicates to return some extra data which will come out in resulting results
            if ok then
                table.insert(ret, { location = { inventory = inventory, slot = slot }, item = item, extra = extra })
            end
        end
    end
    return ret
end

-- Finds space in the chest system. Returns the name of an inventory which has space.
local function find_space()
    for name, items in pairs(index) do
        if #items < inventories[name].size() then
            return name
        end
    end
end

local function find_by_ID_meta(id, meta)
    return find(function(item)
        return 
            (not meta or item.damage == meta) and -- if metadata provided, ensure match
            (not id or item.name == id) -- if internal name provided, ensure match
    end)
end

local function search(query, threshold)
    local threshold = threshold or 4
    local results = find(function(item)
        local distance = d.distance(query, item.display_name)
        if distance < threshold then
            return true, distance
        else return false end
    end)
    return d.sort_by(results, function(x) return x.extra end) -- sort returned results by closeness to query
end

local function fetch_by_location(loc, limit)
    local peripheral_name, slot, limit = loc.inventory, loc.slot, limit or 64
    return peripheral.call(conf.buffer_internal, "pullItems", peripheral_name, slot, limit, BUFFER_OUT_SLOT)
end

local function server(command)
    if command.type == "buffers" then -- Sends the external address of the buffer
        return conf.buffer_external
    elseif command.type == "reindex" then
        os.queueEvent "reindex"
    elseif command.type == "extract" then
        local result = find_by_ID_meta(command.ID, command.meta)
        local first_available = result[1]

        -- Check if we have an item, and its stack is big enough; otherwise, send back an error.
        local quantity_missing = 0
        if not first_available then quantity_missing = command.quantity or 1
        elseif command.quantity and command.quantity > first_available.item.count then quantity_missing = command.quantity - first_available.item.count end
        if quantity_missing > 0 then return w.errors.make(w.errors.NOITEMS, { type = w.get_internal_identifier(command), quantity = quantity_missing }) end

        local items_moved = fetch_by_location(first_available.location, command.quantity)
        if command.destination_inventory then
            items_moved = peripheral.call(conf.buffer_external, "pushItems", command.destination_inventory, BUFFER_OUT_SLOT, command.quantity, command.destination_slot)
        end

        return { moved = items_moved, item = first_available.item }
    end
end

local function indexer_thread()
    while true do
        update_index()
        os.pullEvent "reindex"
    end
end

w.init()
parallel.waitForAll(function() w.serve(server, "storage") end, indexer_thread)