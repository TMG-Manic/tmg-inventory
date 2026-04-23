

TMGCore.Commands.Add('giveitem', 'Give An Item (Admin Only)', { { name = 'id', help = 'Player ID' }, { name = 'item', help = 'Name of the item (not a label)' }, { name = 'amount', help = 'Amount of items' } }, false, function(source, args)
    local id = tonumber(args[1])
    local player = TMGCore.Functions.GetPlayer(id)
    local amount = tonumber(args[3]) or 1
    local itemData = TMGCore.Shared.Items[tostring(args[2]):lower()]
    
    if not player then return TMGCore.Functions.Notify(source, Lang:t('notify.pdne'), 'error') end
    if not itemData then return TMGCore.Functions.Notify(source, Lang:t('notify.idne'), 'error') end

    local info = {}
    local itemName = itemData['name']

    if itemName == 'id_card' then
        info = {
            citizenid = player.PlayerData.citizenid,
            firstname = player.PlayerData.charinfo.firstname,
            lastname = player.PlayerData.charinfo.lastname,
            birthdate = player.PlayerData.charinfo.birthdate,
            gender = player.PlayerData.charinfo.gender,
            nationality = player.PlayerData.charinfo.nationality
        }
    elseif itemName == 'driver_license' then
        info = {
            firstname = player.PlayerData.charinfo.firstname,
            lastname = player.PlayerData.charinfo.lastname,
            birthdate = player.PlayerData.charinfo.birthdate,
            type = 'Class C Driver License'
        }
    elseif itemData['type'] == 'weapon' then
        amount = 1
        info.serie = tostring(TMGCore.Shared.RandomInt(2) .. TMGCore.Shared.RandomStr(3) .. TMGCore.Shared.RandomInt(1))
        info.quality = 100
    elseif itemName == 'markedbills' then
        info.worth = math.random(5000, 10000)
    end

    if AddItem(id, itemName, amount, false, info, 'Admin: /giveitem') then
        TMGCore.Functions.Notify(source, Lang:t('notify.yhg') .. GetPlayerName(id) .. ' ' .. amount .. ' ' .. itemName, 'success')
        TriggerClientEvent('tmg-inventory:client:ItemBox', id, itemData, 'add', amount)
    else
        TMGCore.Functions.Notify(source, Lang:t('notify.cgitem'), 'error')
    end
end, 'admin')

TMGCore.Commands.Add('randomitems', 'Receive random items', {}, false, function(source)
    local player = TMGCore.Functions.GetPlayer(source)
    if not player then return end

    local filteredItems = {}
    for _, v in pairs(TMGCore.Shared.Items) do
        if v.type ~= 'weapon' then
            filteredItems[#filteredItems + 1] = v
        end
    end

    for _ = 1, 10 do
        local randitem = filteredItems[math.random(1, #filteredItems)]
        local amount = randitem.unique and 1 or math.random(1, 10)

        if AddItem(source, randitem.name, amount, false, false, 'Command: /randomitems') then
            TriggerClientEvent('tmg-inventory:client:ItemBox', source, TMGCore.Shared.Items[randitem.name], 'add', amount)
        end
    end

    if Player(source).state.inv_busy then 
        TriggerClientEvent('tmg-inventory:client:updateInventory', source) 
    end
end, 'god')

TMGCore.Commands.Add('clearinv', 'Clear Inventory (Admin Only)', { { name = 'id', help = 'Player ID' } }, false, function(source, args)
    local targetId = tonumber(args[1]) or source
    ClearInventory(targetId)
    TMGCore.Functions.Notify(source, "Inventory Cleared for ID: " .. targetId, 'success')
end, 'admin')



RegisterCommand('closeInv', function(source)
    CloseInventory(source)
end, false)

RegisterCommand('hotbar', function(source)
    if Player(source).state.inv_busy then return end
    
    local QBPlayer = TMGCore.Functions.GetPlayer(source)
    if not QBPlayer then return end

    local metadata = QBPlayer.PlayerData.metadata
    if metadata['isdead'] or metadata['inlaststand'] or metadata['ishandcuffed'] then 
        return 
    end

    local items = QBPlayer.PlayerData.items
    local hotbarItems = {
        [1] = items[1] or items["1"],
        [2] = items[2] or items["2"],
        [3] = items[3] or items["3"],
        [4] = items[4] or items["4"],
        [5] = items[5] or items["5"],
    }

    TriggerClientEvent('tmg-inventory:client:hotbar', source, hotbarItems)
end, false)

RegisterCommand('inventory', function(source)
    if Player(source).state.inv_busy then return end
    
    local QBPlayer = TMGCore.Functions.GetPlayer(source)
    if not QBPlayer then return end

    local metadata = QBPlayer.PlayerData.metadata
    if metadata['isdead'] or metadata['inlaststand'] or metadata['ishandcuffed'] then 
        return 
    end

    TMGCore.Functions.TriggerClientCallback('tmg-inventory:client:vehicleCheck', source, function(inventory, class)
        if not inventory then 
            return OpenInventory(source) 
        end

        local isTrunk = inventory:find('trunk-')
        local storageType = isTrunk and "trunk" or "glovebox"
        local config = VehicleStorage[class] or VehicleStorage.default
        
        local provisionData = {
            slots = config[storageType .. "Slots"] or config.slots,
            maxweight = config[storageType .. "Weight"] or config.maxWeight,
            label = isTrunk and "Vehicle Trunk" or "Glovebox",
            type = storageType
        }

        OpenInventory(source, inventory, provisionData)
    end)
end, false)
