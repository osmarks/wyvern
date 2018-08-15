local d = require "luadash"
local w = require "lib"

local conf = w.load_config({
    "chest",
    "items",
    "sleep_time"
}, {
    sleep_time = 1,
    items = {}
})

w.init()

local chest = peripheral.wrap(conf.chest)

local function get_num_stacks(total_items)
    return math.ceil(total_items / 64)
end

local function main()
    while true do
        local stacks_stored = d.map(d.filter(chest.list(), function(x) return x ~= nil end), w.to_wyvern_item)
        local items_stored = w.collate_stacks(stacks_stored)
        
        local function get_item_count(ii)
            return (items_stored[ii] or {count = 0}).count
        end
        
        for item_name, quantity_desired in pairs(conf.items) do
            local quantity_stocked = get_item_count(item_name)
            if quantity_desired > quantity_stocked then -- if we have fewer items than are desired, extract some from store
                local request = w.string_to_item(item_name)
                request.type = "extract"
                request.destination_inventory = conf.chest
                local result = w.unwrap(w.query_by_type("storage", request), "extracting items", { w.errors.NOITEMS })
                print("Moved", result.moved, item_name, "from storage.")
            end
        end
        
        for slot, item in pairs(stacks_stored) do
            local ii = w.get_internal_identifier(item)
            local stored = get_item_count(ii)
            local wanted = 0
            if conf.items[ii] then wanted = conf.items[ii] + 1 end
            if (get_num_stacks(stored) * 64) >= wanted then -- if item is not in want list or we have too many, send it back to storage
                local result = w.unwrap(w.query_by_type("storage", {
                    type = "insert",
                    from_inventory = conf.chest,
                    from_slot = slot
                }), "inserting items")
                print("Moved", result.moved, ii, "to storage.")
            end
        end
        
        sleep(conf.sleep_time)
    end
end

local ok, err = pcall(main)
if type(err) == "table" then err = w.errors.format(err) end
print(err)