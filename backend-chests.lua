local util = require "util"
local conf = util.conf

rednet.open(conf.modem)

-- Find all chests or shulker boxes
local inventories = {}
for _, n in pairs(peripheral.getNames()) do
    local p = peripheral.wrap(n)
    if 
        string.find(n, "chest") or
        string.find(n, "shulker") then
        inventories[n] = p
    end
end

local nameCache = {}

-- Gets the display name of the given item (in the given chest peripheral & slot)
-- If its name is not cached, cache it.
-- If it is, just return the cached name
function cache(item, chest, slot)
    local idx = item.name .. ":" .. item.damage
    
    if nameCache[idx] then
        return nameCache[idx]
    else
		local n = chest.getItemMeta(slot).displayName
        nameCache[idx] = n
		return n
    end
end

local index = {}
function updateIndexFor(name)
    local inv = inventories[name]
    local data = inv.list()
    
    for slot, item in pairs(data) do
        data[slot].displayName = cache(item, inv, slot)
    end
    
    index[name] = data
end

function updateIndex()
	for n in pairs(inventories) do
		updateIndexFor(n)
		sleep()
	end
	print "Indexing complete."
end

-- Finds all items matching a certain predicate
function find(predicate)
    for name, items in pairs(index) do
        for slot, item in pairs(items) do
            if predicate(item) then
                return name, slot, item
            end
        end
    end
end

-- Finds space in the chest system
function findSpace()
    for name, items in pairs(index) do
        if #items < inventories[name].size() then
            return name
        end
    end
end

function search(msg)
    return find(function(item)
        return 
            (not msg.meta or item.damage == msg.meta) and
            (not msg.name or item.name == msg.name) and
            (not msg.dname or string.find(item.displayName:lower(), msg.dname:lower()))
    end)
end

function processRequest(msg)
    print(textutils.serialise(msg))

    -- Extract an item. If meta and name are supplied, each supplied value must match exactly.
    -- Applies a fuzzy search to display names
    -- Extracted items are either deposited in buffer or directly in target inventory.
    if msg.cmd == "extract" then
        local inv, slot, item = search(msg)

        local qty = msg.qty or 64

		updateIndexFor(inv)

		local moved = peripheral.call(conf.bufferOutInternal, "pullItems", inv, slot, qty, 1)

		if msg.destInv then
			moved = peripheral.call(conf.bufferOutExternal, "pushItems", msg.destInv, 1, 64, msg.destSlot)
		end

        return {moved, item}
    -- Pulls items from an external inventory into storage.
	elseif msg.cmd == "insert" then
		if msg.fromInv and msg.fromSlot then
			peripheral.call(conf.bufferInExternal, "pullItems", msg.fromInv, msg.fromSlot, msg.qty or 64, 1)
		end

		local toInv = findSpace()
		if not toInv then return "ERROR" end
		
		peripheral.call(conf.bufferInInternal, "pushItems", toInv, 1)

		updateIndexFor(toInv) -- I don't know a good way to figure out where exactly the items went

        return "OK"
    -- Just return the external network names of the buffers
	elseif msg.cmd == "buffers" then
        return { conf.bufferInExternal, conf.bufferOutExternal }
    -- Reindexes system
	elseif msg.cmd == "reindex" then
		updateIndex()
        return "OK"
    -- Returns entire index
    elseif msg.cmd == "list" then
        return util.collate(index)
    -- Looks up supplied name in the cache.
    elseif msg.cmd == "name" then
        msg.meta = msg.meta or 0
        return msg.name and msg.meta and nameCache[msg.name .. ":" .. msg.meta]
    end
end

function processRequests()
    while true do
        util.processMessage(function(msg)
            local ok, r = pcall(processRequest, msg)
            if not ok then r = "ERROR" end

            return true, r
        end)
    end
end

updateIndex()
processRequests()