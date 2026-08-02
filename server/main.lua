TMGCore = exports['tmg-core']:GetCoreObject()
Inventories = {}
Drops = {}
RegisteredShops = {}

local function getIdentifier(inventoryId, src)
    if inventoryId == 'player' then
        return src
    elseif inventoryId:find('otherplayer-') then
        return tonumber(inventoryId:match('otherplayer%-(.+)'))
    else
        return inventoryId
    end
end

local function getItem(inventoryId, src, slot)
    local items = nil
    slot = tonumber(slot)
    if not slot then return nil end

    if inventoryId == 'player' then
        local Player = TMGCore.Functions.GetPlayer(src)
        if Player then items = Player.PlayerData.items end
    elseif inventoryId:find('otherplayer-') then
        local targetId = tonumber(inventoryId:match('otherplayer%-(.+)'))
        local targetPlayer = TMGCore.Functions.GetPlayer(targetId)
        if targetPlayer then items = targetPlayer.PlayerData.items end
    elseif inventoryId:find('drop-') == 1 then
        if Drops[inventoryId] then items = Drops[inventoryId].items end
    else
        if not Inventories[inventoryId] then
            local data = exports['tmgnosql']:FetchOne('inventories', {
                ["identifier"] = inventoryId
            })
            if data then
                Inventories[inventoryId] = {
                    ["items"] = data.items,
                    ["isOpen"] = false
                }
            end
        end
        if Inventories[inventoryId] then items = Inventories[inventoryId].items end
    end

    if items then
        for _, item in pairs(items) do
            if item and tonumber(item.slot) == slot then
                return item
            end
        end
    end
    return nil
end

CreateThread(function()
    print("^2[TMG]^7 Inventory System Initialized. Data optimized for BSON storage.")
end)

CreateThread(function()
    local result = exports['tmgnosql']:FetchAll('inventories', {})
    
    if result and #result > 0 then
        for i = 1, #result do
            local inventory = result[i]
            local cacheKey = inventory.identifier
            
            Inventories[cacheKey] = {
                ["items"] = inventory.items or {},
                ["isOpen"] = false
            }
        end
        print(string.format("^5[TMG]^7 Mainframe: %d persistent stashes anchored to RAM.", #result))
    end
end)

CreateThread(function()
    while true do
        local currentTime = os.time()
        local cleanupCount = 0
        
        for k, v in pairs(Drops) do
            local isExpired = (v.createdTime + (Config.CleanupDropTime * 60) < currentTime)
            
            if v and isExpired and not v.isOpen then
                if #v.items > 0 then
                    exports['tmgnosql']:InsertOne('expired_drops', {
                        ["dropId"] = k,
                        ["final_contents"] = v.items,
                        ["coords"] = v.coords,
                        ["spawnedTime"] = v.createdTime,
                        ["cleanupTime"] = currentTime,
                        ["reason"] = "Scheduled Mainframe Purge"
                    })
                end
                local entity = NetworkGetEntityFromNetworkId(v.entityId)
                if DoesEntityExist(entity) then 
                    DeleteEntity(entity) 
                end
                Drops[k] = nil
                cleanupCount = cleanupCount + 1
            end
        end
        if cleanupCount > 0 then
            print(string.format("^5[TMG]^7 Mainframe: Volatile Purge complete. %d drops archived.", cleanupCount))
        end
        Wait(Config.CleanupDropInterval * 60000)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    SaveInventory(src)
    for _, inv in pairs(Inventories) do
        if inv.isOpen == src then
            inv.isOpen = false
        end
    end
end)

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
        print(string.format("^5[TMG]^7 Mainframe: Inventory synchronized for CID %s", PlayerData.citizenid))
    else
        print(string.format("^1[TMG]^7 Mainframe Error: Failed to synchronize inventory for CID %s", PlayerData.citizenid))
    end
end
exports('SaveInventory', SaveInventory)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    local count = 0
    local startTime = os.time()
    
    print("^3[TMG]^7 Mainframe: Emergency shutdown signal received. Initiating Data Vaulting...")
    for inventoryId, data in pairs(Inventories) do
        if data and data.items then
            exports['tmgnosql']:SaveToCollection('inventories', 
                { ["identifier"] = inventoryId }, 
                { ["items"] = data.items }
            )
            count = count + 1
        end
    end
    local duration = os.time() - startTime
    if count > 0 then
        print(string.format("^2[TMG]^7 Vaulting Complete: %d inventories anchored in %ds. Mainframe Safe.", count, duration))
        print("^5[TMG]^7 Integrity Check: All Volatile RAM sectors flushed to Persistent Storage.")
    else
        print("^5[TMG]^7 Standby: No active delta detected in RAM. Shutdown authorized.")
    end
end)

RegisterNetEvent('TMGCore:Server:UpdateObject', function()
    if source ~= '' then return end
    TMGCore = exports['tmg-core']:GetCoreObject()
end)

AddEventHandler('TMGCore:Server:PlayerLoaded', function(Player)
    local src = Player.PlayerData.source
    
    TMGCore.Functions.AddPlayerMethod(src, 'AddItem', function(item, amount, slot, info, reason)
        return AddItem(src, item, amount, slot, info, reason)
    end)
    TMGCore.Functions.AddPlayerMethod(src, 'RemoveItem', function(item, amount, slot, reason)
        return RemoveItem(src, item, amount, slot, reason)
    end)
    TMGCore.Functions.AddPlayerMethod(src, 'GetItemBySlot', function(slot)
        return GetItemBySlot(src, slot)
    end)
    TMGCore.Functions.AddPlayerMethod(src, 'GetItemByName', function(item)
        return GetItemByName(src, item)
    end)
    TMGCore.Functions.AddPlayerMethod(src, 'GetItemsByName', function(item)
        return GetItemsByName(src, item)
    end)
    TMGCore.Functions.AddPlayerMethod(src, 'ClearInventory', function(filterItems)
        ClearInventory(src, filterItems)
    end)
    TMGCore.Functions.AddPlayerMethod(src, 'SetInventory', function(items)
        SetInventory(src, items)
    end)
    
    print(string.format("^2[TMG]^7 Methods injected for [%s] %s", src, Player.PlayerData.charinfo.firstname))
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    
    local Players = TMGCore.Functions.GetTMGPlayers()
    local count = 0
    for k, v in pairs(Players) do
        local src = v.PlayerData.source
        TMGCore.Functions.AddPlayerMethod(src, 'AddItem', function(item, amount, slot, info)
            return AddItem(src, item, amount, slot, info)
        end)
        TMGCore.Functions.AddPlayerMethod(src, 'RemoveItem', function(item, amount, slot)
            return RemoveItem(src, item, amount, slot)
        end)
        TMGCore.Functions.AddPlayerMethod(src, 'GetItemBySlot', function(slot)
            return GetItemBySlot(src, slot)
        end)
        TMGCore.Functions.AddPlayerMethod(src, 'GetItemByName', function(item)
            return GetItemByName(src, item)
        end)
        TMGCore.Functions.AddPlayerMethod(src, 'GetItemsByName', function(item)
            return GetItemsByName(src, item)
        end)
        TMGCore.Functions.AddPlayerMethod(src, 'ClearInventory', function(filterItems)
            ClearInventory(src, filterItems)
        end)
        TMGCore.Functions.AddPlayerMethod(src, 'SetInventory', function(items)
            SetInventory(src, items)
        end)
        Player(src).state.inv_busy = false
        
        count = count + 1
    end
    print(string.format("^2[TMG]^7 Resource Restarted: Re-linked %s players to the Mainframe.", count))
end)

function checkWeapon(source, item)
    local currentWeapon = type(item) == 'table' and item.name or item
    local ped = GetPlayerPed(source)
    local weaponHash = GetSelectedPedWeapon(ped)
    local weaponInfo = TMGCore.Shared.Weapons[weaponHash]

    if weaponInfo and weaponInfo.name == currentWeapon then
        RemoveWeaponFromPed(ped, weaponHash)

        TriggerClientEvent('tmg-weapons:client:UseWeapon', source, { ["name"] = currentWeapon }, false)

        exports['tmgnosql']:InsertDocument('weapon_logs', {
            ["src"] = source,
            ["citizenid"] = TMGCore.Functions.GetPlayer(source).PlayerData.citizenid,
            ["weapon"] = currentWeapon,
            ["action"] = "forced_holster",
            ["reason"] = "inventory_manipulation",
            ["timestamp"] = os.time()
        })

        print(string.format("^5[TMG]^7 Mainframe: Forced holster successful for CID %s [%s]",
        TMGCore.Functions.GetPlayer(source).PlayerData.citizenid, currentWeapon))
    end
end

RegisterNetEvent('tmg-inventory:server:openVending', function(data)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local shopId = 'vending_standard'
    
    if not RegisteredShops[shopId] then
        CreateShop({
            ["name"] = shopId,
            ["label"] = 'Vending Machine',
            ["coords"] = data.coords,
            ["slots"] = #Config.VendingItems,
            ["items"] = Config.VendingItems
        })
    end
    OpenShop(src, shopId)
    exports['tmgnosql']:UpdateOne('vending_stats', 
        { ["machine"] = shopId }, 
        { ["$inc"] = { ["total_opens"] = 1 } }, 
        { ["upsert"] = true }
    )
    
    print(string.format("^5[TMG]^7 Mainframe: Vending Interaction Logged | Shop: %s | CID: %s", shopId, Player.PlayerData.citizenid))
end)

RegisterNetEvent('tmg-inventory:client:openInventory', function(inventory, other)
    local playerPed = PlayerPedId()
    
    -- Enable mouse cursor and keyboard focus
    SetNuiFocus(true, true)
    
    -- Send data to Vue (app.js)
    SendNUIMessage({
        action = "open",
        inventory = inventory,
        other = other,
        maxweight = Config.MaxWeight,
        slots = Config.MaxSlots
    })
    
    -- Play inventory opening animation
    RequestAnimDict("pickup_object")
    while not HasAnimDictLoaded("pickup_object") do Wait(0) end
    TaskPlayAnim(playerPed, "pickup_object", "putdown_low", 8.0, -8.0, -1, 48, 0, false, false, false)
end)

RegisterNetEvent('tmg-inventory:server:closeInventory', function(inventoryId)
    local src = source
    local TMGPlayer = TMGCore.Functions.GetPlayer(src)
    if not TMGPlayer or not inventoryId then return end

    -- FiveM native state bag call works cleanly now
    Player(src).state.inv_busy = false
    SaveInventory(src)
    if inventoryId:find('shop%-') then return end

    if inventoryId:find('otherplayer%-') then
        local targetId = tonumber(inventoryId:match('otherplayer%-(.+)'))
        if targetId then 
            Player(targetId).state.inv_busy = false 
        end
        return
    end

    if Drops[inventoryId] then
        Drops[inventoryId].isOpen = false
        
        if #Drops[inventoryId].items == 0 then 
            TriggerClientEvent('tmg-inventory:client:removeDropTarget', -1, Drops[inventoryId].entityId)
            Wait(500)
            local entity = NetworkGetEntityFromNetworkId(Drops[inventoryId].entityId)
            if DoesEntityExist(entity) then DeleteEntity(entity) end
            Drops[inventoryId] = nil
        end
        return
    end

    if Inventories[inventoryId] then
        Inventories[inventoryId].isOpen = false
        
        exports['tmgnosql']:UpdateOne('inventories', 
            { ["identifier"] = inventoryId }, 
            { ["$set"] = { ["items"] = Inventories[inventoryId].items } },
            { ["upsert"] = true }
        )
        
        print(string.format("^5[TMG]^7 Mainframe: Container '%s' synchronized.", inventoryId))
    end
end)

RegisterNetEvent('tmg-inventory:server:useItem', function(item)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local itemData = GetItemBySlot(src, item.slot)
    if not itemData then return end
    
    local itemInfo = TMGCore.Shared.Items[itemData.name]
    if not itemInfo then return end
    if itemData.type == 'weapon' then
        local hasQuality = itemData.info.quality and itemData.info.quality > 0
        TriggerClientEvent('tmg-weapons:client:UseWeapon', src, itemData, hasQuality)
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, itemInfo, 'use')
    elseif itemData.name == 'id_card' or itemData.name == 'driver_license' then
        UseItem(itemData.name, src, itemData)
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, itemInfo, 'use')
        local playerCoords = GetEntityCoords(GetPlayerPed(src))
        local players = TMGCore.Functions.GetPlayers()
        
        local info = itemData.info
        local isID = (itemData.name == 'id_card')
        
        for _, v in pairs(players) do
            local targetPed = GetPlayerPed(v)
            if #(playerCoords - GetEntityCoords(targetPed)) < 3.0 then
                if isID then
                    TriggerClientEvent('chat:addMessage', v, {
                        template = '<div class="chat-message advert" style="background: linear-gradient(to right, rgba(5, 5, 5, 0.6), #74807c); padding: 5px; border-radius: 5px;"><strong>ID Card:</strong> {0} {1}<br><strong>Civ ID:</strong> {2}<br><strong>Nationality:</strong> {3}</div>',
                        args = { info.firstname, info.lastname, info.citizenid, info.nationality }
                    })
                else
                    TriggerClientEvent('chat:addMessage', v, {
                        template = '<div class="chat-message advert" style="background: linear-gradient(to right, rgba(5, 5, 5, 0.6), #657175); padding: 5px; border-radius: 5px;"><strong>Driver License:</strong> {0} {1}<br><strong>Date of Birth:</strong> {2}<br><strong>Type:</strong> {3}</div>',
                        args = { info.firstname, info.lastname, info.birthdate, info.type }
                    })
                end
            end
        end
    else
        UseItem(itemData.name, src, itemData)
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, itemInfo, 'use')
    end
end)

RegisterNetEvent('tmg-inventory:server:openDrop', function(dropId)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local drop = Drops[dropId]
    if not drop then 
        TriggerClientEvent('TMGCore:Notify', src, "This supply bag has already been reclaimed.", 'error')
        return 
    end
    if drop.isOpen then 
        TriggerClientEvent('TMGCore:Notify', src, "Another citizen is currently searching this bag.", 'error')
        return 
    end
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local distance = #(playerCoords - drop.coords)
    
    if distance > 2.5 then 
        TriggerClientEvent('TMGCore:Notify', src, "You are too far from the bag to search it.", 'error')
        return 
    end
    local formattedInventory = {
        ["name"] = dropId,
        ["label"] = "Dropped Items",
        ["maxweight"] = drop.maxweight,
        ["slots"] = drop.slots,
        ["inventory"] = drop.items 
    }
    drop.isOpen = true
    
    exports['tmgnosql']:UpdateOne('drop_logs', 
        { ["dropId"] = dropId }, 
        { 
            ["$set"] = { 
                ["last_opened_by"] = Player.PlayerData.citizenid,
                ["last_opened_at"] = os.time()
            } 
        },
        { ["upsert"] = true }
    )
    TriggerClientEvent('tmg-inventory:client:openInventory', src, Player.PlayerData.items, formattedInventory)
    
    print(string.format("^5[TMG]^7 Mainframe: Drop Interaction | CID: %s | ID: %s", Player.PlayerData.citizenid, dropId))
end)

RegisterNetEvent('tmg-inventory:server:snowball', function(action)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local itemName = 'weapon_snowball'
    if action == 'add' then
        if CanAddItem(src, itemName, 1) then
            AddItem(src, itemName, 1, false, false, 'tmg-inventory:server:snowball')
        else
            TriggerClientEvent('TMGCore:Notify', src, "Your pockets are too full for more snow!", 'error')
        end
    elseif action == 'remove' then
        RemoveItem(src, itemName, 1, false, 'tmg-inventory:server:snowball')
    end
end)

TMGCore.Functions.CreateCallback('tmg-inventory:server:GetCurrentDrops', function(_, cb)
    cb(Drops)
end)

-- 1. Create Drop Server Callback
TMGCore.Functions.CreateCallback('tmg-inventory:server:createDrop', function(source, cb, item)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not item or not item.name then return cb(false) end

    local playerPed = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    local fromSlot = tonumber(item.fromSlot) or tonumber(item.slot)

    if RemoveItem(src, item.name, item.amount, fromSlot, 'dropped item') then
        if item.type == 'weapon' then checkWeapon(src, item) end

        local bag = CreateObjectNoOffset(Config.ItemDropObject, playerCoords.x + 0.2, playerCoords.y + 0.2, playerCoords.z, true, true, false)
        local netId = NetworkGetNetworkIdFromEntity(bag)
        local newDropId = 'drop-' .. netId

        if not Drops[newDropId] then
            Drops[newDropId] = {
                ["name"] = newDropId,
                ["label"] = 'Drop',
                ["items"] = { item },
                ["entityId"] = netId,
                ["createdTime"] = os.time(),
                ["coords"] = playerCoords,
                ["maxweight"] = Config.DropSize.maxweight,
                ["slots"] = Config.DropSize.slots,
                ["isOpen"] = false
            }
            TriggerClientEvent('tmg-inventory:client:setupDropTarget', -1, netId)
        else
            table.insert(Drops[newDropId].items, item)
        end

        exports['tmgnosql']:InsertDocument('active_drops', Drops[newDropId])

        cb(netId) -- Returns raw netId so client can resolve NetworkGetEntityFromNetworkId
    else
        cb(false)
    end
end)

-- 2. Update Bag Position Event (Triggers when placing bag down with G)
RegisterNetEvent('tmg-inventory:server:updateDrop', function(dropId, newCoords)
    if Drops[dropId] then
        Drops[dropId].coords = newCoords
        exports['tmgnosql']:UpdateOne('active_drops',
            { ["name"] = dropId },
            { ["$set"] = { ["coords"] = newCoords } }
        )
    end
end)

TMGCore.Functions.CreateCallback('tmg-inventory:server:attemptPurchase', function(source, cb, data)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    
    if not Player or not data.amount or tonumber(data.amount) <= 0 then 
        return cb(false) 
    end
    local itemInfo = data.item
    local amount = tonumber(data.amount)
    local shopId = string.gsub(data.shop, 'shop%-', '')
    local shopData = RegisteredShops[shopId]
    if not shopData then return cb(false) end
    local pCoords = GetEntityCoords(GetPlayerPed(src))
    if shopData.coords and #(pCoords - vector3(shopData.coords.x, shopData.coords.y, shopData.coords.z)) > 10 then
        return cb(false) 
    end
    local slotData = shopData.items[itemInfo.slot]
    if not slotData or slotData.name ~= itemInfo.name then return cb(false) end
    if amount > slotData.amount or slotData.amount <= 0 then
        TriggerClientEvent('TMGCore:Notify', src, 'Mainframe: Supply shortage at this location.', 'error')
        return cb(false)
    end
    if not CanAddItem(src, itemInfo.name, amount) then
        TriggerClientEvent('TMGCore:Notify', src, 'Mainframe: Personal storage capacity exceeded.', 'error')
        return cb(false)
    end
    local totalPrice = slotData.price * amount
    if Player.PlayerData.money.cash >= totalPrice then
        Player.Functions.RemoveMoney('cash', totalPrice, 'shop-purchase')
        AddItem(src, itemInfo.name, amount, nil, itemInfo.info, 'shop-purchase')
        slotData.amount = slotData.amount - amount
        
        exports['tmgnosql']:UpdateOne('shops', 
            { 
                ["name"] = shopId, 
                ["items.slot"] = itemInfo.slot 
            }, 
            { 
                ["$inc"] = { 
                    ["items.$.amount"] = -amount 
                } 
            }
        )
        TriggerEvent('tmg-shops:server:UpdateShopItems', shopId, itemInfo, amount)
        cb(true)
        
        exports['tmgnosql']:InsertDocument('economy_logs', {
            ["type"] = "purchase",
            ["cid"] = Player.PlayerData.citizenid,
            ["amount"] = totalPrice,
            ["item"] = itemInfo.name,
            ["quantity"] = amount,
            ["timestamp"] = os.time()
        })
    else
        TriggerClientEvent('TMGCore:Notify', src, 'Mainframe: Financial credentials rejected (Insufficient Cash).', 'error')
        cb(false)
    end
end)

TMGCore.Functions.CreateCallback('tmg-inventory:server:giveItem', function(source, cb, target, item, amount, slot, info)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    local Target = TMGCore.Functions.GetPlayer(target)
    if not Player or Player.PlayerData.metadata['isdead'] or Player.PlayerData.metadata['ishandcuffed'] then return cb(false) end
    if not Target or Target.PlayerData.metadata['isdead'] or Target.PlayerData.metadata['ishandcuffed'] then return cb(false) end
    local pPed, tPed = GetPlayerPed(src), GetPlayerPed(target)
    if #(GetEntityCoords(pPed) - GetEntityCoords(tPed)) > 5 then return cb(false) end
    local itemName = item:lower()
    local itemInfo = TMGCore.Shared.Items[itemName]
    local giveAmount = tonumber(amount)
    if not itemInfo or not giveAmount or giveAmount <= 0 then return cb(false) end
    local playerItem = GetItemByName(src, itemName)
    if not playerItem or playerItem.amount < giveAmount then return cb(false) end
    local removed = RemoveItem(src, itemName, giveAmount, slot, 'Given to ID: ' .. target)
    if not removed then return cb(false) end
    local added = AddItem(target, itemName, giveAmount, false, info, 'Received from ID: ' .. src)
    if not added then
        AddItem(src, itemName, giveAmount, slot, info, 'Target full, item returned')
        return cb(false)
    end
    if itemInfo.type == 'weapon' then checkWeapon(src, itemName) end
    TriggerClientEvent('tmg-inventory:client:giveAnim', src)
    TriggerClientEvent('tmg-inventory:client:ItemBox', src, itemInfo, 'remove', giveAmount)
    
    TriggerClientEvent('tmg-inventory:client:giveAnim', target)
    TriggerClientEvent('tmg-inventory:client:ItemBox', target, itemInfo, 'add', giveAmount)
    if Player(target).state.inv_busy then 
        TriggerClientEvent('tmg-inventory:client:updateInventory', target) 
    end
    cb(true)
end)

local function getItem(inventoryId, src, slot)
    local items = nil
    slot = tonumber(slot)
    if not slot then return nil end

    if inventoryId == 'player' then
        local Player = TMGCore.Functions.GetPlayer(src)
        if Player then items = Player.PlayerData.items end
    elseif inventoryId:find('otherplayer-') then
        local targetId = tonumber(inventoryId:match('otherplayer%-(.+)'))
        local targetPlayer = TMGCore.Functions.GetPlayer(targetId)
        if targetPlayer then items = targetPlayer.PlayerData.items end
    elseif inventoryId:find('drop-') == 1 then
        if Drops[inventoryId] then items = Drops[inventoryId].items end
    else
        if not Inventories[inventoryId] then
            local data = exports['tmgnosql']:FetchOne('inventories', {
                ["identifier"] = inventoryId
            })
            if data then
                Inventories[inventoryId] = {
                    ["items"] = data.items,
                    ["isOpen"] = false
                }
            end
        end
        if Inventories[inventoryId] then items = Inventories[inventoryId].items end
    end

    if items then
        for _, item in pairs(items) do
            -- tonumber ensures string slot keys ("1") match numeric slot IDs (1)
            if item and tonumber(item.slot) == slot then
                return item
            end
        end
    end
    return nil
end

RegisterNetEvent('tmg-inventory:server:SetInventoryData', function(fromInv, toInv, fromSlot, toSlot, fromAmount, toAmount)
    if toInv:find('shop%-') then return end

    local src = source
    local TMGPlayer = TMGCore.Functions.GetPlayer(src)

    if not TMGPlayer then return end

    fromSlot, toSlot = tonumber(fromSlot), tonumber(toSlot)
    fromAmount, toAmount = tonumber(fromAmount), tonumber(toAmount)

    if not fromSlot or not toSlot or fromAmount < 0 or toAmount < 0 then return end

    Player(src).state.inv_busy = true

    local fromItem = getItem(fromInv, src, fromSlot)
    local toItem = getItem(toInv, src, toSlot)

    if fromItem then
        if toAmount > fromItem.amount then
            Player(src).state.inv_busy = false
            return
        end

        if fromInv == 'player' and toInv ~= 'player' then checkWeapon(src, fromItem) end
        local fromId = getIdentifier(fromInv, src)
        local toId = getIdentifier(toInv, src)

        -- 1. Stacking onto an existing matching item
        if toItem and fromItem.name == toItem.name then
            if RemoveItem(fromId, fromItem.name, toAmount, fromSlot, 'stacked item') then
                AddItem(toId, toItem.name, toAmount, toSlot, toItem.info, 'stacked item')
            end
        -- 2. Splitting a stack into an empty slot
        elseif not toItem and toAmount < fromItem.amount then
            if RemoveItem(fromId, fromItem.name, toAmount, fromSlot, 'split item') then
                AddItem(toId, fromItem.name, toAmount, toSlot, fromItem.info, 'split item')
            end
        -- 3. Swapping two different items or moving entire stack
        else
            if toItem then
                local fromAmountReal = fromItem.amount
                local toAmountReal = toItem.amount
                if RemoveItem(fromId, fromItem.name, fromAmountReal, fromSlot, 'swapped-out') and
                    RemoveItem(toId, toItem.name, toAmountReal, toSlot, 'swapped-in') then

                    AddItem(toId, fromItem.name, fromAmountReal, toSlot, fromItem.info, 'swapped-final')
                    AddItem(fromId, toItem.name, toAmountReal, fromSlot, toItem.info, 'swapped-final')
                end
            else
                if RemoveItem(fromId, fromItem.name, toAmount, fromSlot, 'moved item') then
                    local added = AddItem(toId, fromItem.name, toAmount, toSlot, fromItem.info, 'moved item')

                    if not added then
                        AddItem(fromId, fromItem.name, toAmount, fromSlot, fromItem.info, 'move failed - returned')
                    end
                end
            end
        end

        -- Immediately save player inventory whenever items are split or moved
        if fromInv == 'player' or toInv == 'player' then
            SaveInventory(src)
        end
    end

    Player(src).state.inv_busy = false
end)