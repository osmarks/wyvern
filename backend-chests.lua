-- Chest backend
-- Currently just the one for Dragon. Will not actually work yet.

local w = require "lib"
local d = require "luadash"

local conf = w.load_config({
    "buffer_internal",
    "buffer_external"
}, {
    modem_internal = nil
})

local BUFFER_OUT_SLOT = 1
local BUFFER_IN_SLOT = 2

-- Find all chests or shulker boxes
local inventories = d.map_with_key(w.find_peripherals(function(type, name, wrapped)
    return string.find(name, "chest") or string.find(name, "shulker")
end, conf.modem_internal), function(_, p) return p.name, p.wrapped end)

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

local function to_wyvern_item(plethora_item)
    return { NBT = plethora_item.nbtHash, ID = plethora_item.name, damage = plethora_item, display_name = plethora_item.displayName, count = plethora_item.count }
end

local index = {}
-- Update the index for the given peripheral
local function update_index_for(name)
    local inv = inventories[name]
    local data = inv.list()
    
    for slot, item in pairs(data) do
        data[slot] = to_wyvern_item(data[slot])
        data[slot].display_name = cache(item, inv, slot)
    end
    
    index[name] = data

    print("Indexed " .. name .. ".")
end

-- Reindex all connected inventories
local function update_index()
    print "Full indexing started."
	for n in pairs(inventories) do
        update_index_for(n)
		sleep()
	end
	print "Full indexing complete."
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

local function find_by_ID_meta_NBT(ID, meta, NBT)
    return find(function(item)
        return 
            (not meta or item.meta == meta) and -- if metadata provided, ensure match
            (not ID or item.ID == ID) and -- if internal name provided, ensure match
            (not NBT or item.NBT == NBT) -- if NBT hash provided, ensure match
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

-- Retrives items from a location in storage and puts them in the buffer
local function fetch_by_location(loc, limit)
    local peripheral_name, slot, limit = loc.inventory, loc.slot, limit or 64
    return peripheral.call(conf.buffer_internal, "pullItems", peripheral_name, slot, limit, BUFFER_OUT_SLOT)
end

-- Clears out the buffer into storage.
local function clear_buffer()
    for i = 1, peripheral.call(conf.buffer_internal, "size") do
        local space_location = find_space()
        if not space_location then error("Storage capacity reached. Please add more chests or shulker boxes.") end
        peripheral.call(conf.buffer_internal, "pushItems", space_location, i)
        os.queueEvent("reindex", space_location)
        sleep()
    end
end

local function server(command)
    if command.type == "buffers" then -- Sends the external address of the buffer
        return conf.buffer_external
    elseif command.type == "reindex" then
        os.queueEvent "reindex"
    elseif command.type == "extract" then
        local result = find_by_ID_meta_NBT(command.ID, command.meta, command.NBT)
        local first_available = result[1]

        -- Check if we have an item, and its stack is big enough; otherwise, send back an error.
        local quantity_missing = 0
        if not first_available then quantity_missing = command.quantity or 1
        elseif command.quantity and command.quantity > first_available.item.count then quantity_missing = command.quantity - first_available.item.count end
        if quantity_missing > 0 then return w.errors.make(w.errors.NOITEMS, { type = w.get_internal_identifier(command), quantity = quantity_missing }) end

        local items_moved_from_storage = fetch_by_location(first_available.location, command.quantity)

        os.queueEvent("reindex", first_available.location.inventory) -- I'm too lazy to manually update the item properly, and indexing is fast enough, so just do this

        if command.destination_inventory then
            -- push items to destination
            items_moved_to_destination = peripheral.call(conf.buffer_external, "pushItems", command.destination_inventory, BUFFER_OUT_SLOT, command.quantity, command.destination_slot)

            -- If destination didn't accept all items, clear out the buffer.
            if items_moved_to_destination < items_moved_from_storage then
                clear_buffer()
            end
        end

        return { moved = items_moved_to_destination or items_moved_from_storage, item = to_wyvern_item(first_available.item) }
    elseif command.type == "insert" then
        local inventory_with_space = find_space()
        if not inventory_with_space then return w.errors.make(w.errors.NOSPACE) end -- if there's not space, say so in error

        if command.from_inventory and command.from_slot then
            peripheral.call(conf.buffer_external, "pullItems", command.from_inventory, command.from_slot, command.quantity, BUFFER_IN_SLOT) -- pull from from_inventory to buffer
        end

        local moved = peripheral.call(conf.buffer_internal, "pushItems", inventory_with_space, BUFFER_IN_SLOT) -- push from buffer to free space

        if moved == 0 then clear_buffer() end -- if for some reason it broke and there's no space, clear out buffer
        os.queueEvent("reindex", inventory_with_space)

        return { moved = moved }
    elseif command.type == "search" then
        return w.collate_stacks(d.map(search(command.query, command.threshold), function(x) return x.item end))
    elseif command.type == "list" then
        return index
    end
end

local function indexer_thread()
    while true do
        local _, inventory = os.pullEvent "reindex"
        if inventory then update_index_for(inventory) else update_index() end
    end
end

w.init()
parallel.waitForAll(function() os.queueEvent("reindex") w.serve(server, "storage") end, indexer_thread)