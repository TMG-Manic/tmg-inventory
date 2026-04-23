TMGCore = exports['tmg-core']:GetCoreObject()



InvState = {
    PlayerData = TMGCore.Functions.GetPlayerData(),
    isLoggedIn = LocalPlayer.state['isLoggedIn'],
    hotbarShown = false,
    
    HoldingDrop = false,
    bagObject = nil,
    heldDropId = nil,
    CurrentDrop = nil,
    
    BackEngineVehicles = BackEngineVehicles or {}
}



function LoadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(10) end
end

local function FormatWeaponAttachments(itemdata)
    if not itemdata.info or not itemdata.info.attachments or #itemdata.info.attachments == 0 then return {} end
    local attachments, weaponName = {}, itemdata.name
    local WeaponConfig = exports['tmg-weapons']:getConfigWeaponAttachments()
    if not WeaponConfig then return {} end
    for attachmentType, weapons in pairs(WeaponConfig) do
        local componentHash = weapons[weaponName]
        if componentHash then
            for _, attachmentData in pairs(itemdata.info.attachments) do
                if attachmentData.component == componentHash then
                    attachments[#attachments + 1] = {
                        attachment = attachmentType,
                        label = TMGCore.Shared.Items[attachmentType] and TMGCore.Shared.Items[attachmentType].label or 'Unknown'
                    }
                end
            end
        end
    end
    return attachments
end



function HasItem(items, amount)
    local isTable = type(items) == 'table'
    local isArray = isTable and table.type(items) == 'array' or false
    local totalItems, count = 0, 0
    if isTable and not isArray then for _ in pairs(items) do totalItems = totalItems + 1 end else totalItems = isArray and #items or 0 end
    if InvState.PlayerData and type(InvState.PlayerData.items) == "table" then
        for _, itemData in pairs(InvState.PlayerData.items) do
            if isTable then
                for k, v in pairs(items) do
                    if itemData and itemData.name == (isArray and v or k) and ((amount and itemData.amount >= amount) or (not isArray and itemData.amount >= v) or (not amount and isArray)) then
                        count = count + 1
                        if count == totalItems then return true end
                    end
                end
            else
                if itemData and itemData.name == items and (not amount or (itemData.amount >= amount)) then return true end
            end
        end
    end
    return false
end
exports('HasItem', HasItem)



function GetDrops()
    TMGCore.Functions.TriggerCallback('tmg-inventory:server:GetCurrentDrops', function(drops)
        if not drops then return end
        for k, v in pairs(drops) do
            local bag = NetworkGetEntityFromNetworkId(v.entityId)
            if DoesEntityExist(bag) then
                exports['tmg-target']:AddTargetEntity(bag, {
                    options = {{ icon = 'fas fa-backpack', label = Lang:t('menu.o_bag'), action = function() TriggerServerEvent('tmg-inventory:server:openDrop', k) InvState.CurrentDrop = k end }},
                    distance = 2.5,
                })
            end
        end
        print("^5[TMG]^7 Spatial drops synchronized.")
    end)
end



local function IsBackEngine(vehModel) return InvState.BackEngineVehicles[vehModel] end

local function OpenTrunk(vehicle)
    LoadAnimDict('amb@prop_human_bum_bin@idle_b')
    TaskPlayAnim(PlayerPedId(), 'amb@prop_human_bum_bin@idle_b', 'idle_d', 4.0, 4.0, -1, 50, 0, false, false, false)
    SetVehicleDoorOpen(vehicle, IsBackEngine(GetEntityModel(vehicle)) and 4 or 5, false, false)
end

function CloseTrunk()
    local vehicle, distance = TMGCore.Functions.GetClosestVehicle()
    if vehicle == 0 or distance > 5 then return end
    LoadAnimDict('amb@prop_human_bum_bin@idle_b')
    TaskPlayAnim(PlayerPedId(), 'amb@prop_human_bum_bin@idle_b', 'exit', 4.0, 4.0, -1, 50, 0, false, false, false)
    SetVehicleDoorShut(vehicle, IsBackEngine(GetEntityModel(vehicle)) and 4 or 5, false)
end



CreateThread(function()
    while true do
        local sleep = 1000
        if InvState.HoldingDrop then
            sleep = 0
            if IsControlJustPressed(0, 47) then 
                DetachEntity(InvState.bagObject, true, true)
                local coords = GetEntityCoords(PlayerPedId())
                local x, y, z = table.unpack(coords + GetEntityForwardVector(PlayerPedId()) * 0.57)
                SetEntityCoords(InvState.bagObject, x, y, z - 0.9, false, false, false, false)
                FreezeEntityPosition(InvState.bagObject, true)
                exports['tmg-core']:HideText()
                TriggerServerEvent('tmg-inventory:server:updateDrop', InvState.heldDropId, coords)
                InvState.HoldingDrop, InvState.bagObject, InvState.heldDropId = false, nil, nil
            end
        end
        Wait(sleep)
    end
end)



RegisterNetEvent('TMGCore:Client:OnPlayerLoaded', function()
    LocalPlayer.state:set('inv_busy', false, true)
    InvState.PlayerData = TMGCore.Functions.GetPlayerData()
    InvState.isLoggedIn = true
    GetDrops()
end)

RegisterNetEvent('tmg-inventory:client:setupDropTarget', function(dropId)
    while not NetworkDoesNetworkIdExist(dropId) do Wait(10) end
    local bag = NetworkGetEntityFromNetworkId(dropId)
    while not DoesEntityExist(bag) do Wait(10) end
    local newDropId = 'drop-' .. dropId
    exports['tmg-target']:AddTargetEntity(bag, {
        options = {
            { icon = 'fas fa-backpack', label = Lang:t('menu.o_bag'), action = function() TriggerServerEvent('tmg-inventory:server:openDrop', newDropId) InvState.CurrentDrop = newDropId end },
            { icon = 'fas fa-hand-pointer', label = 'Pick up bag', action = function()
                if IsPedArmed(PlayerPedId(), 4) then return TMGCore.Functions.Notify("You can not be holding a Gun and a Bag!", "error", 5500) end
                if InvState.HoldingDrop then return TMGCore.Functions.Notify("Your already holding a bag!", "error", 5500) end
                AttachEntityToEntity(bag, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), Config.ItemDropObjectBone), Config.ItemDropObjectOffset[1].x, Config.ItemDropObjectOffset[1].y, Config.ItemDropObjectOffset[1].z, Config.ItemDropObjectOffset[2].x, Config.ItemDropObjectOffset[2].y, Config.ItemDropObjectOffset[2].z, true, true, false, true, 1, true)
                InvState.bagObject, InvState.HoldingDrop, InvState.heldDropId = bag, true, newDropId
                exports['tmg-core']:DrawText('Press [G] to drop the bag')
            end }
        }, distance = 2.5
    })
end)

RegisterNetEvent('tmg-inventory:client:removeDropTarget', function(id)
    while not NetworkDoesNetworkIdExist(id) do Wait(10) end
    local bag = NetworkGetEntityFromNetworkId(id)
    if DoesEntityExist(bag) then exports['tmg-target']:RemoveTargetEntity(bag) end
end)

RegisterNetEvent('tmg-inventory:client:requiredItems', function(items, bool)
    local itemTable = {}
    if bool then
        for k in pairs(items) do itemTable[#itemTable + 1] = { item = items[k].name, label = TMGCore.Shared.Items[items[k].name]['label'], image = items[k].image } end
    end
    SendNUIMessage({ action = 'requiredItem', items = itemTable, toggle = bool })
end)

RegisterNetEvent('tmg-inventory:server:RobPlayer', function(TargetId)
    SendNUIMessage({ action = 'RobMoney', TargetId = TargetId })
end)

RegisterNetEvent('tmg-inventory:client:giveAnim', function()
    if IsPedInAnyVehicle(PlayerPedId(), false) then return end
    LoadAnimDict('mp_common')
    TaskPlayAnim(PlayerPedId(), 'mp_common', 'givetake1_b', 8.0, 1.0, -1, 16, 0, false, false, false)
end)



RegisterNUICallback('CloseInventory', function(data, cb)
    SetNuiFocus(false, false)
    if data.name and data.name:find('trunk-') then CloseTrunk() end
    TriggerServerEvent('tmg-inventory:server:closeInventory', data.name or InvState.CurrentDrop)
    InvState.CurrentDrop = nil
    cb('ok')
end)

RegisterNUICallback('GiveItem', function(data, cb)
    local player, distance = TMGCore.Functions.GetClosestPlayer(GetEntityCoords(PlayerPedId()))
    if player ~= -1 and distance < 3 then
        TMGCore.Functions.TriggerCallback('tmg-inventory:server:giveItem', function(success) cb(success) end, GetPlayerServerId(player), data.item.name, data.amount, data.slot, data.info)
    else TMGCore.Functions.Notify(Lang:t('notify.nonb'), 'error') cb(false) end
end)

RegisterNUICallback('GetWeaponData', function(cData, cb)
    cb({ WeaponData = TMGCore.Shared.Items[cData.weapon], AttachmentData = FormatWeaponAttachments(cData.ItemData) })
end)

RegisterNUICallback('RemoveAttachment', function(data, cb)
    local WeaponData, allAttachments = data.WeaponData, exports['tmg-weapons']:getConfigWeaponAttachments()
    local Attachment = allAttachments[data.AttachmentData.attachment][WeaponData.name]
    TMGCore.Functions.TriggerCallback('tmg-weapons:server:RemoveAttachment', function(NewAttachments)
        RemoveWeaponComponentFromPed(PlayerPedId(), joaat(WeaponData.name), joaat(Attachment))
        if NewAttachments then
            local Attachies = {}
            for _, v in pairs(NewAttachments) do
                for type, weapons in pairs(allAttachments) do
                    if weapons[WeaponData.name] and v.component == weapons[WeaponData.name] then
                        Attachies[#Attachies + 1] = { attachment = type, label = TMGCore.Shared.Items[type].label or 'Unknown' }
                    end
                end
            end
            cb({ Attachments = Attachies, WeaponData = WeaponData, itemInfo = TMGCore.Shared.Items[data.AttachmentData.attachment] })
        else cb({}) end
    end, data.AttachmentData, WeaponData)
end)



TMGCore.Functions.CreateClientCallback('tmg-inventory:client:vehicleCheck', function(cb)
    local ped = PlayerPedId()
    local inVeh = GetVehiclePedIsIn(ped, false)
    if inVeh ~= 0 then cb('glovebox-' .. GetVehicleNumberPlateText(inVeh), GetVehicleClass(inVeh)) return end

    local veh, dist = TMGCore.Functions.GetClosestVehicle()
    if veh ~= 0 and dist < 5 then
        local pos, min, max = GetEntityCoords(ped), GetModelDimensions(GetEntityModel(veh))
        local trunkpos = GetOffsetFromEntityInWorldCoords(veh, 0.0, IsBackEngine(GetEntityModel(veh)) and max.y or min.y, 0.0)
        if #(pos - trunkpos) < 1.5 then
            if GetVehicleDoorLockStatus(veh) < 2 then OpenTrunk(veh) cb('trunk-' .. GetVehicleNumberPlateText(veh), GetVehicleClass(veh))
            else TMGCore.Functions.Notify(Lang:t('notify.vlocked'), 'error') end
            return
        end
    end
    cb(nil)
end)



for i = 1, 5 do
    RegisterCommand('slot_' .. i, function()
        local item = InvState.PlayerData.items[i]
        if item then
            if item.type == "weapon" and InvState.HoldingDrop then return TMGCore.Functions.Notify("Your already holding a bag, Go Drop it!", "error", 5500) end
            TriggerServerEvent('tmg-inventory:server:useItem', item)
        end
    end)
    RegisterKeyMapping('slot_' .. i, Lang:t('inf_mapping.use_item') .. i, 'keyboard', tostring(i))
end

RegisterKeyMapping('openInv', Lang:t('inf_mapping.opn_inv'), 'keyboard', Config.Keybinds.Open)
