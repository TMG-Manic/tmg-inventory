local function InitializeInventory(inventoryId, data)
    Inventories[inventoryId] = {
        items = {},
        isOpen = false,
        label = data and data.label or inventoryId,
        maxweight = data and data.maxweight or Config.StashSize.maxweight,
        slots = data and data.slots or Config.StashSize.slots
    }
    return Inventories[inventoryId]
end

local function GetFirstFreeSlot(items, maxSlots)
    for i = 1, maxSlots do
        if items[i] == nil then
            return i
        end
    end
    return nil
end

local function SetupShopItems(shopItems)
    local items = {}
    local slot = 1
    if shopItems and next(shopItems) then
        for _, item in pairs(shopItems) do
            local itemInfo = TMGCore.Shared.Items[item.name:lower()]
            if itemInfo then
                items[slot] = {
                    name = itemInfo['name'],
                    amount = tonumber(item.amount),
                    info = item.info or {},
                    label = itemInfo['label'],
                    description = itemInfo['description'] or '',
                    weight = itemInfo['weight'],
                    type = itemInfo['type'],
                    unique = itemInfo['unique'],
                    useable = itemInfo['useable'],
                    price = item.price,
                    image = itemInfo['image'],
                    slot = slot,
                }
                slot = slot + 1
            end
        end
    end
    return items
end

function LoadInventory(source, citizenid)
    local result = exports['tmgnosql']:FetchOne('players', { 
        ["citizenid"] = citizenid 
    }, { ["inventory"] = 1 })
    
    local loadedInventory = {}
    local missingItems = {}
    local rawInventory = result and result.inventory or {}
    for slot, item in pairs(rawInventory) do
        if item and item.name then
            local itemName = item.name:lower()
            local itemInfo = TMGCore.Shared.Items[itemName]
            if itemInfo then
                loadedInventory[tonumber(slot)] = {
                    ["name"] = itemInfo.name,
                    ["amount"] = tonumber(item.amount) or 1,
                    ["info"] = item.info or {},
                    ["label"] = itemInfo.label,
                    ["description"] = itemInfo.description or '',
                    ["weight"] = itemInfo.weight,
                    ["type"] = itemInfo.type,
                    ["unique"] = itemInfo.unique,
                    ["useable"] = itemInfo.useable,
                    ["image"] = itemInfo.image,
                    ["shouldClose"] = itemInfo.shouldClose,
                    ["slot"] = tonumber(slot),
                    ["combinable"] = itemInfo.combinable
                }
            else
                missingItems[#missingItems + 1] = itemName
            end
        end
    end
    if #missingItems > 0 then
        local identifier = source and GetPlayerName(source) or citizenid
        print(string.format("^5[TMG]^7 Mainframe: Purged %d orphaned items for %s | [%s]", 
            #missingItems, identifier, table.concat(missingItems, ', ')))
    end
    return loadedInventory
end
exports('LoadInventory', LoadInventory)

function SaveInventory(source, offline)
    local PlayerData
    
    if offline then
        PlayerData = source
    else
        local Player = TMGCore.Functions.GetPlayer(source)
        if not Player then return end
        PlayerData = Player.PlayerData
    end

    local items = PlayerData.items
    local saveTable = {}
    local itemCount = 0

    if items and next(items) then
        for slot, item in pairs(items) do
            if item then
                local slotNum = tonumber(item.slot or slot)
                if slotNum then
                    saveTable[tostring(slotNum)] = {
                        ["name"] = item.name,
                        ["amount"] = tonumber(item.amount) or 1,
                        ["info"] = item.info or {},
                        ["type"] = item.type,
                        ["slot"] = slotNum,
                    }
                    itemCount = itemCount + 1
                end
            end
        end
    end

    local success = exports['tmgnosql']:UpdateOne('players', 
        { ["citizenid"] = PlayerData.citizenid }, 
        { ["$set"] = { ["inventory"] = saveTable } },
        { ["upsert"] = true }
    )

    if success then
        TriggerEvent('tmg-log:server:CreateLog', 'playerinventory', 'Inventory Synced', 'blue', 
    string.format("CID: %s | Items Saved: %d | Offline: %s", 
    PlayerData.citizenid, itemCount, tostring(offline)))
            
        print(string.format("^5[TMG]^7 Mainframe: Inventory synchronized for CID %s (%d items)", PlayerData.citizenid, itemCount))
    else
        print(string.format("^1[TMG]^7 Mainframe Error: Failed to synchronize inventory for CID %s", PlayerData.citizenid))
    end
end
exports('SaveInventory', SaveInventory)

function SetInventory(identifier, items, reason)
    local targetType = "unknown"
    local citizenid = nil
    local player = TMGCore.Functions.GetPlayer(identifier)

    if player then
        targetType = "player"
        citizenid = player.PlayerData.citizenid
        player.Functions.SetPlayerData('items', items)
        SaveInventory(identifier)
        
    elseif Inventories[identifier] then
        targetType = "stash"
        Inventories[identifier].items = items
        exports['tmgnosql']:UpdateOne('inventories', 
            { ["identifier"] = identifier }, 
            { ["$set"] = { ["items"] = items } },
            { ["upsert"] = true }
        )
        
    elseif Drops[identifier] then
        targetType = "drop"
        Drops[identifier].items = items
        
    else
        print("^1[TMG]^7 SetInventory Critical: Target '" .. tostring(identifier) .. "' not registered in Mainframe.")
        return
    end

    local setReason = reason or 'No reason specified'
    local invokingResource = GetInvokingResource() or 'tmg-inventory'
    
    exports['tmgnosql']:InsertDocument('inventory_audit', {
        ["target"] = identifier,
        ["type"] = targetType,
        ["citizenid"] = citizenid,
        ["items"] = items,
        ["reason"] = setReason,
        ["resource"] = invokingResource,
        ["timestamp"] = os.time()
    })

    local logLabel = player and (GetPlayerName(identifier) .. " (" .. citizenid .. ")") or identifier
    TriggerEvent('tmg-log:server:CreateLog', 'inventory', 'State Override', 'blue', 
        string.format("Target: %s | Type: %s | Reason: %s | Trigger: %s", 
        logLabel, targetType, setReason, invokingResource))
end
exports('SetInventory', SetInventory)

function CloseInventory(source, identifier)
    -- Always save the player's own inventory state on close
    SaveInventory(source)

    if identifier and Inventories[identifier] then
        Inventories[identifier].isOpen = false
        local items = Inventories[identifier].items
        exports['tmgnosql']:UpdateOne('inventories', 
            { ["identifier"] = identifier }, 
            { ["$set"] = { ["items"] = items } }
        )
        print(string.format("^5[TMG]^7 Mainframe: Container '%s' state anchored.", tostring(identifier)))
    end

    Player(source).state.inv_busy = false
    TriggerClientEvent('tmg-inventory:client:closeInv', source)
    print(string.format("^5[TMG]^7 Session: Closed and Synced interaction for %s", tostring(identifier or "Self")))
end
exports('CloseInventory', CloseInventory)

function SetItemData(source, itemName, key, val, slot)
    if not itemName or not key then return false end
    
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return false end
    local item
    if slot then
        item = Player.PlayerData.items[tonumber(slot)]
        if not item or item.name:lower() ~= itemName:lower() then return false end
    else
        item = GetItemByName(source, itemName)
        if not item then return false end
    end
    item[key] = val
    Player.PlayerData.items[item.slot] = item
    local updatePath = string.format("inventory.%d.%s", item.slot, key)
    
    exports['tmgnosql']:UpdateOne('players', 
        { ["citizenid"] = Player.PlayerData.citizenid }, 
        { ["$set"] = { [updatePath] = val } }
    )
    Player.Functions.SetPlayerData('items', Player.PlayerData.items)
    
    print(string.format("^5[TMG]^7 Mainframe: Item Data Updated | CID: %s | Item: %s | Key: %s", Player.PlayerData.citizenid, itemName, key))
    return true
end
exports('SetItemData', SetItemData)

function UseItem(itemName, ...)
    local src = source
    local itemNameLower = itemName:lower()
    
    local itemData = TMGCore.Functions.CanUseItem(itemNameLower)
    
    if type(itemData) == 'table' and itemData.func then
        if Player(src).state.inv_busy then 
            return false 
        end
        local success, err = pcall(function(...)
            itemData.func(...)
        end, ...)
        if not success then
            print(string.format("^1[TMG Mainframe]^7 Error executing UseItem for %s: %s", itemNameLower, err))
            return false
        end
        return true
    end
    print(string.format("^3[TMG Mainframe]^7 Item %s has no registered 'use' function.", itemNameLower))
    return false
end
exports('UseItem', UseItem)

function GetSlotsByItem(items, itemName)
    local slotsFound = {}
    if not items or not itemName then return slotsFound end
    
    local searchName = itemName:lower()
    for slot, item in pairs(items) do
        if item and item.name and item.name:lower() == searchName then
            slotsFound[#slotsFound + 1] = tonumber(slot)
        end
    end
    return slotsFound
end
exports('GetSlotsByItem', GetSlotsByItem)

function GetFirstSlotByItem(items, itemName)
    if not items or not itemName then return nil end
    
    local searchName = itemName:lower()
    for i = 1, Config.MaxSlots do
        local item = items[i]
        if item and item.name and item.name:lower() == searchName then
            return i
        end
    end
    return nil
end
exports('GetFirstSlotByItem', GetFirstSlotByItem)

function GetItemBySlot(source, slot)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player or not slot then return nil end
    
    local slotId = tonumber(slot)
    if not slotId then return nil end
    local items = Player.PlayerData.items
    local item = items[slotId]
    if item and item.slot ~= slotId then
        item.slot = slotId
    end
    return item
end
exports('GetItemBySlot', GetItemBySlot)

function GetTotalWeight(items)
    if not items or not next(items) then return 0 end
    
    local weight = 0.0
    for _, item in pairs(items) do
        if item and item.weight then
            local amount = tonumber(item.amount) or 1
            local itemWeight = tonumber(item.weight) or 0.0
            weight = weight + (itemWeight * amount)
        end
    end
    return tonumber(string.format("%.2f", weight))
end
exports('GetTotalWeight', GetTotalWeight)

function GetItemByName(source, item)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player or not item then return nil end
    local items = Player.PlayerData.items
    local itemName = tostring(item):lower()
    for i = 1, Config.MaxSlots do
        local slotData = items[i]
        if slotData and slotData.name and slotData.name:lower() == itemName then
            return slotData
        end
    end
    return nil
end
exports('GetItemByName', GetItemByName)

function GetItemsByName(source, item)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player or not item then return {} end
    local PlayerItems = Player.PlayerData.items
    local searchName = tostring(item):lower()
    local foundItems = {}
    for i = 1, Config.MaxSlots do
        local slotData = PlayerItems[i]
        if slotData and slotData.name and slotData.name:lower() == searchName then
            foundItems[#foundItems + 1] = slotData
        end
    end
    return foundItems
end
exports('GetItemsByName', GetItemsByName)

function GetSlots(identifier)
    local inventory = nil
    local maxSlots = Config.MaxSlots
    local player = TMGCore.Functions.GetPlayer(identifier)
    
    if player then
        inventory = player.PlayerData.items
        maxSlots = Config.MaxSlots
    elseif Inventories[identifier] then
        inventory = Inventories[identifier].items
        maxSlots = Inventories[identifier].slots or Config.StashSize.slots
    elseif Drops[identifier] then
        inventory = Drops[identifier].items
        maxSlots = Drops[identifier].slots or Config.DropSize.slots
    end
    if not inventory then return 0, maxSlots end
    local slotsUsed = 0
    
    for i = 1, maxSlots do
        if inventory[i] ~= nil then
            slotsUsed = slotsUsed + 1
        end
    end
    local slotsFree = maxSlots - slotsUsed
    if slotsFree < 0 then slotsFree = 0 end
    return slotsUsed, slotsFree
end
exports('GetSlots', GetSlots)

function GetItemCount(source, items)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return 0 end
    local PlayerItems = Player.PlayerData.items
    local count = 0
    if type(items) == 'table' then
        local itemsSet = {}
        for i = 1, #items do
            itemsSet[items[i]:lower()] = true
        end
        for i = 1, Config.MaxSlots do
            local itemData = PlayerItems[i]
            if itemData and itemsSet[itemData.name:lower()] then
                count = count + (tonumber(itemData.amount) or 0)
            end
        end
    else
        local itemName = tostring(items):lower()
        for i = 1, Config.MaxSlots do
            local itemData = PlayerItems[i]
            if itemData and itemData.name:lower() == itemName then
                count = count + (tonumber(itemData.amount) or 0)
            end
        end
    end
    return count
end
exports('GetItemCount', GetItemCount)

function CanAddItem(identifier, item, amount)
    local itemName = item:lower()
    local itemData = TMGCore.Shared.Items[itemName]
    if not itemData then return false end
    local inventory = nil
    local items = nil
    local maxWeight = Config.MaxWeight
    local maxSlots = Config.MaxSlots
    local Player = TMGCore.Functions.GetPlayer(identifier)
    if Player then
        inventory = Player.PlayerData
        items = Player.PlayerData.items
    elseif Inventories[identifier] then
        inventory = Inventories[identifier]
        items = Inventories[identifier].items
        maxWeight = inventory.maxweight or Config.StashSize.maxweight
        maxSlots = inventory.slots or Config.StashSize.slots
    else
        print("^1[TMG Mainframe]^7 CanAddItem: Target document not found (" .. tostring(identifier) .. ")")
        return false
    end
    local incomingWeight = (tonumber(itemData.weight) or 0) * (tonumber(amount) or 1)
    local currentWeight = GetTotalWeight(items)
    if (currentWeight + incomingWeight) > maxWeight then
        return false, 'weight'
    end
    local slotsUsed, slotsFree = GetSlots(identifier)
    if slotsFree > 0 then return true end
    if not itemData.unique then
        for i = 1, maxSlots do
            local existingItem = items[i]
            if existingItem and existingItem.name:lower() == itemName then
                return true
            end
        end
    end
    return false, 'slots'
end
exports('CanAddItem', CanAddItem)

function GetFreeWeight(source)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then 
        warn('[TMG Mainframe] Source not found for GetFreeWeight: ' .. tostring(source))
        return 0 
    end
    local currentWeight = GetTotalWeight(Player.PlayerData.items)
    local freeWeight = Config.MaxWeight - currentWeight
    if freeWeight < 0 then freeWeight = 0 end
    return freeWeight
end
exports('GetFreeWeight', GetFreeWeight)

function ClearInventory(source, filterItems)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    local preservedItems = {}
    if filterItems then
        if type(filterItems) == 'string' then
            local item = GetItemByName(source, filterItems)
            if item then preservedItems[tostring(item.slot)] = item end
        elseif type(filterItems) == 'table' then
            for _, itemName in ipairs(filterItems) do
                local item = GetItemByName(source, itemName)
                if item then preservedItems[tostring(item.slot)] = item end
            end
        end
    end
    Player.Functions.SetPlayerData('items', preservedItems)
    local success = exports['tmgnosql']:UpdateOne('players', 
        { ["citizenid"] = citizenid }, 
        { ["$set"] = { ["inventory"] = preservedItems } }
    )
    if not Player.Offline then
        local logMessage = string.format('**%s (CID: %s)** inventory purged. Preserved: %s', 
            GetPlayerName(source), citizenid, (filterItems and "YES" or "NONE"))
        TriggerEvent('tmg-log:server:CreateLog', 'inventory', 'Wipe', 'red', logMessage)
        
        local ped = GetPlayerPed(source)
        local weapon = GetSelectedPedWeapon(ped)
        if weapon ~= `WEAPON_UNARMED` then
            RemoveWeaponFromPed(ped, weapon)
        end
        
        TriggerClientEvent('tmg-inventory:client:updateInventory', source)
    end
    print(string.format("^5[TMG]^7 Mainframe: Inventory Purge Node executed for CID %s", citizenid))
end
exports('ClearInventory', ClearInventory)

function HasItem(source, items, amount)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player or not items then return false end
    local PlayerItems = Player.PlayerData.items
    local isTable = type(items) == 'table'
    local reqAmount = tonumber(amount) or 1
    local checklist = {}
    local requirementsCount = 0
    if isTable then
        local isArray = table.type(items) == 'array'
        if isArray then
            for i = 1, #items do
                local name = items[i]:lower()
                checklist[name] = (checklist[name] or 0) + reqAmount
                requirementsCount = requirementsCount + 1
            end
        else
            for name, itemReqAmount in pairs(items) do
                local lowerName = name:lower()
                checklist[lowerName] = (checklist[lowerName] or 0) + (tonumber(itemReqAmount) or 1)
                requirementsCount = requirementsCount + 1
            end
        end
    else
        checklist[items:lower()] = reqAmount
        requirementsCount = 1
    end
    local itemsFound = 0
    local foundTracker = {} 
    for i = 1, Config.MaxSlots do
        local itemData = PlayerItems[i]
        if itemData and checklist[itemData.name:lower()] then
            local name = itemData.name:lower()
            foundTracker[name] = (foundTracker[name] or 0) + itemData.amount
            if foundTracker[name] >= checklist[name] then
                if foundTracker[name] - itemData.amount < checklist[name] then
                    itemsFound = itemsFound + 1
                end
            end
        end
        if itemsFound == requirementsCount then return true end
    end
    return false
end
exports('HasItem', HasItem)


function OpenInventoryById(source, targetId)
    local QBPlayer = TMGCore.Functions.GetPlayer(source)
    local TargetPlayer = TMGCore.Functions.GetPlayer(tonumber(targetId))
    if not QBPlayer or not TargetPlayer then 
        return print("^1[TMG Mainframe]^7 OpenInventoryById: Target not found ("..tostring(targetId)..")")
    end
    if Player(targetId).state.inv_busy then 
        CloseInventory(targetId) 
    end
    local playerItems = QBPlayer.PlayerData.items
    local targetItems = TargetPlayer.PlayerData.items
    local targetCitizenId = TargetPlayer.PlayerData.citizenid
    local formattedInventory = {
        name = 'otherplayer-' .. targetCitizenId, 
        label = GetPlayerName(targetId),
        maxweight = Config.MaxWeight,
        slots = Config.MaxSlots,
        inventory = targetItems
    }
    Player(targetId).state.inv_busy = true
    TriggerClientEvent('tmg-inventory:client:openInventory', source, playerItems, formattedInventory)
end
exports('OpenInventoryById', OpenInventoryById)

function ClearStash(identifier)
    if not identifier then return end
    local inventory = Inventories[identifier]
    if not inventory then 
        return print("^1[TMG]^7 ClearStash: Target container '"..tostring(identifier).."' not active in RAM.")
    end
    inventory.items = {}
    local success = exports['tmgnosql']:UpdateOne('inventories', 
        { ["identifier"] = identifier }, 
        { ["$set"] = { ["items"] = {} } }
    )
    if success then
        TriggerClientEvent('tmg-inventory:client:updateInventory', -1)
        print("^2[TMG]^7 Mainframe: Stash Purge successfully anchored for node: " .. identifier)
        TriggerEvent('tmg-log:server:CreateLog', 'stashes', 'Stash Purged', 'red', 
            string.format("Container: %s | Action: Full Wipe", identifier))
    else
        print("^1[TMG]^7 Mainframe Error: Failed to anchor purge for container: " .. identifier)
    end
end
exports('ClearStash', ClearStash)

function CreateShop(shopData)
    if shopData.name then
        local shopName = shopData.name
        RegisteredShops[shopName] = {
            ["name"] = shopName,
            ["label"] = shopData.label or "Mainframe Store",
            ["coords"] = shopData.coords,
            ["slots"] = #shopData.items,
            ["items"] = SetupShopItems(shopData.items) 
        }
        exports['tmgnosql']:UpdateOne('shared_shops', 
            { ["name"] = shopName }, 
            { ["$set"] = RegisteredShops[shopName] }, 
            { ["upsert"] = true }
        )
        print(string.format("^5[TMG]^7 Mainframe: Retail Node Registered -> %s", shopName))
    else
        for key, data in pairs(shopData) do
            if type(data) == 'table' then
                if data.name then
                    local shopName = type(key) == 'number' and data.name or key
                    RegisteredShops[shopName] = {
                        ["name"] = shopName,
                        ["label"] = data.label or "Mainframe Store",
                        ["coords"] = data.coords,
                        ["slots"] = #data.items,
                        ["items"] = SetupShopItems(data.items)
                    }
                    exports['tmgnosql']:UpdateOne('shared_shops', 
                        { ["name"] = shopName }, 
                        { ["$set"] = RegisteredShops[shopName] }, 
                        { ["upsert"] = true }
                    )
                else
                    CreateShop(data)
                end
            end
        end
    end
end
exports('CreateShop', CreateShop)

function OpenShop(source, name)
    if not name then return end
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return end
    local shop = RegisteredShops[name]
    if not shop then 
        return print("^1[TMG Mainframe]^7 OpenShop: Shop catalog not found (" .. tostring(name) .. ")")
    end
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    if shop.coords then
        local shopVector = vector3(shop.coords.x, shop.coords.y, shop.coords.z)
        local distance = #(playerCoords - shopVector)
        if distance > 10.0 then 
            return print(string.format("^1[TMG]^7 Distance Mismatch: %s is %.2fm away from shop %s", GetPlayerName(source), distance, name))
        end
    end
    local formattedInventory = {
        name = 'shop-' .. shop.name,
        label = shop.label or "Mainframe Store",
        maxweight = 5000000, 
        slots = shop.slots or #shop.items,
        inventory = shop.items 
    }
    TriggerClientEvent('tmg-inventory:client:openInventory', source, Player.PlayerData.items, formattedInventory)
end
exports('OpenShop', OpenShop)

function OpenInventory(source, identifier, data)
    if Player(source).state.inv_busy then return end
    local QBPlayer = TMGCore.Functions.GetPlayer(source)
    if not QBPlayer then return end
    if not identifier then
        Player(source).state.inv_busy = true
        TriggerClientEvent('tmg-inventory:client:openInventory', source, QBPlayer.PlayerData.items)
        return
    end
    if type(identifier) ~= 'string' then
        return print("^1[TMG Mainframe]^7 Error: Invalid inventory identifier type.")
    end
    local inventory = Inventories[identifier]
    if inventory and inventory.isOpen then
        return TriggerClientEvent('TMGCore:Notify', source, 'Inventory in use by another session', 'error')
    end
    if not inventory then 
        inventory = InitializeInventory(identifier, data) 
    end
    inventory.maxweight = (data and data.maxweight) or inventory.maxweight or Config.StashSize.maxweight
    inventory.slots = (data and data.slots) or inventory.slots or Config.StashSize.slots
    inventory.label = (data and data.label) or inventory.label or identifier
    inventory.isOpen = source 
    local formattedInventory = {
        name = identifier,
        label = inventory.label,
        maxweight = inventory.maxweight,
        slots = inventory.slots,
        inventory = inventory.items 
    }
    TriggerClientEvent('tmg-inventory:client:openInventory', source, QBPlayer.PlayerData.items, formattedInventory)
    exports['tmgnosql']:UpdateOne('inventories', 
        { identifier = identifier }, 
        { ["$set"] = { lastOpenedBy = QBPlayer.PlayerData.citizenid } }
    )
end
exports('OpenInventory', OpenInventory)

function CreateInventory(identifier, data)
    if Inventories[identifier] then return end
    if not identifier then return end
    Inventories[identifier] = InitializeInventory(identifier, data)
    exports['tmgnosql']:UpdateOne('inventories', 
        { identifier = identifier }, 
        { 
            ["$set"] = { 
                identifier = identifier,
                label = (data and data.label) or identifier,
                maxweight = (data and data.maxweight) or Config.StashSize.maxweight,
                slots = (data and data.slots) or Config.StashSize.slots,
                type = (data and data.type) or "stash"
            } 
        }, 
        { upsert = true }
    )
    print("^5[TMG]^7 Provisioned new BSON space: " .. identifier)
end
exports('CreateInventory', CreateInventory)

function GetInventory(identifier)
    if not identifier or type(identifier) ~= 'string' then 
        return nil 
    end
    local inventory = Inventories[identifier]
    if inventory and not inventory.items then
        inventory.items = {}
    end
    return inventory
end
exports('GetInventory', GetInventory)

function RemoveInventory(identifier)
    if not identifier or not Inventories[identifier] then return end
    local items = Inventories[identifier].items
    exports['tmgnosql']:UpdateOne('inventories', 
        { identifier = identifier }, 
        { ["$set"] = { items = items } }
    )
    Inventories[identifier] = nil
    print("^5[TMG]^7 De-provisioned BSON space from memory: " .. identifier)
end
exports('RemoveInventory', RemoveInventory)

function AddItem(identifier, item, amount, slot, info, reason)
    local itemName = item:lower()
    local itemInfo = TMGCore.Shared.Items[itemName]
    if not itemInfo then 
        print('^1[TMG Mainframe]^7 AddItem: Invalid item ('..tostring(item)..')')
        return false 
    end
    local inventory, inventoryWeight, inventorySlots, collection, filterKey
    local player = TMGCore.Functions.GetPlayer(identifier)
    if player then
        inventory = player.PlayerData.items
        inventoryWeight = Config.MaxWeight
        inventorySlots = Config.MaxSlots
        collection = 'players'
        filterKey = { citizenid = player.PlayerData.citizenid } 
    elseif Inventories[identifier] then
        inventory = Inventories[identifier].items
        inventoryWeight = Inventories[identifier].maxweight
        inventorySlots = Inventories[identifier].slots
        collection = 'inventories'
        filterKey = { identifier = identifier }
    elseif Drops[identifier] then
        inventory = Drops[identifier].items
        inventoryWeight = Drops[identifier].maxweight
        inventorySlots = Drops[identifier].slots
    end
    if not inventory then return false end
    local totalWeight = GetTotalWeight(inventory)
    if totalWeight + (itemInfo.weight * amount) > inventoryWeight then
        return false 
    end
    amount = tonumber(amount) or 1
    local updated = false
    local targetSlot = slot
    if not itemInfo.unique then
        targetSlot = targetSlot or GetFirstSlotByItem(inventory, itemName)
        if targetSlot and inventory[targetSlot] then
            inventory[targetSlot].amount = inventory[targetSlot].amount + amount
            updated = true
        end
    end
    if not updated then
        targetSlot = targetSlot or GetFirstFreeSlot(inventory, inventorySlots)
        if not targetSlot then return false end
        inventory[targetSlot] = {
            name = itemName,
            amount = amount,
            info = info or {},
            label = itemInfo.label,
            weight = itemInfo.weight,
            type = itemInfo.type,
            unique = itemInfo.unique,
            useable = itemInfo.useable,
            image = itemInfo.image,
            slot = targetSlot,
        }
        if itemInfo.type == 'weapon' then
            if not inventory[targetSlot].info.serie then
                inventory[targetSlot].info.serie = tostring(TMGCore.Shared.RandomInt(2) .. TMGCore.Shared.RandomStr(3) .. TMGCore.Shared.RandomInt(1))
            end
            inventory[targetSlot].info.quality = inventory[targetSlot].info.quality or 100
        end
    end
    if collection then
        local fieldPath = (collection == 'players') and "inventory." or "items."
        exports['tmgnosql']:UpdateOne(collection, filterKey, {
            ["$set"] = {
                [fieldPath .. tostring(targetSlot)] = inventory[targetSlot]
            }
        })
    end
    if player then player.Functions.SetPlayerData('items', inventory) end
    
    local addReason = reason or 'No reason specified'
    TriggerEvent('tmg-log:server:CreateLog', 'playerinventory', 'Item Added', 'green', 
        string.format("**Target:** %s\n**Item:** %s\n**Amt:** %d\n**Slot:** %s\n**Reason:** %s", 
        identifier, itemName, amount, tostring(targetSlot), addReason))
    return true
end
exports('AddItem', AddItem)

function RemoveItem(identifier, item, amount, slot, reason)
    local itemName = item:lower()
    if not TMGCore.Shared.Items[itemName] then return false end
    local inventory, collection, filterKey
    local player = TMGCore.Functions.GetPlayer(identifier)
    if player then
        inventory = player.PlayerData.items
        collection = 'players'
        filterKey = { citizenid = player.PlayerData.citizenid }
    elseif Inventories[identifier] then
        inventory = Inventories[identifier].items
        collection = 'inventories'
        filterKey = { identifier = identifier }
    elseif Drops[identifier] then
        inventory = Drops[identifier].items
    end
    if not inventory then return false end

    local targetSlot = tonumber(slot) or GetFirstSlotByItem(inventory, itemName)
    if not targetSlot then return false end

    -- Check both numeric and string keys to prevent nil lookup failures
    local inventoryItem = inventory[targetSlot] or inventory[tostring(targetSlot)]
    if not inventoryItem then return false end

    local remAmount = tonumber(amount) or 1
    if inventoryItem.amount < remAmount then return false end
    local isFullRemoval = (inventoryItem.amount == remAmount)
    local fieldPath = (collection == 'players') and "inventory." or "items."
    local updateOperation = {}

    if isFullRemoval then
        inventory[targetSlot] = nil
        inventory[tostring(targetSlot)] = nil
        updateOperation = { ["$unset"] = { [fieldPath .. tostring(targetSlot)] = "" } }
    else
        inventoryItem.amount = inventoryItem.amount - remAmount
        updateOperation = { ["$set"] = { [fieldPath .. tostring(targetSlot) .. ".amount"] = inventoryItem.amount } }
    end

    if collection then
        exports['tmgnosql']:UpdateOne(collection, filterKey, updateOperation)
    end

    if player then
        player.Functions.SetPlayerData('items', inventory)
        local itemInfo = TMGCore.Shared.Items[itemName]
        if itemInfo and itemInfo.type == 'weapon' and isFullRemoval then
            checkWeapon(identifier, itemName)
        end
    end

    local removeReason = reason or 'No reason specified'
    TriggerEvent('tmg-log:server:CreateLog', 'playerinventory', 'Item Removed', 'red',
        string.format("**Target:** %s\n**Item:** %s\n**Amt:** %d\n**Slot:** %s\n**Reason:** %s",
        identifier, itemName, remAmount, tostring(targetSlot), removeReason))

    return true
end