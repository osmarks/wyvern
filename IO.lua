local d = require "luadash"
local w = require "lib"

local conf = w.load_config({
    "chest",
    "items"
}, {
    items = {}
})

w.init()

local chest = peripheral.wrap(conf.chest)

while true do
    local stacks_stored = chest.list()
    local items_stored = w.collate_stacks(stacks_stored)

    for item_name, quantity_desired in pairs(conf.items) do
        local quantity_stocked = items_stored[item_name] or 0
        if quantity_desired > quantity_stocked then -- if we have fewer items than are desired, extract some from store
            local request = w.string_to_item(item_name)
            request.type = "extract"
            request.destination_inventory = w.chest
            w.query_by_type("storage", request)
        end
    end

    for slot, item in pairs(stacks_stored) do
        if not items[get_internal_identifier(item)] then -- if item is not in want list, send it back to storage
            w.query_by_type("storage", {
                type = "insert",
                from_inventory = conf.chest,
                from_slot = slot
            })
        end
    end
end