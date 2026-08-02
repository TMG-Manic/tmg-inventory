HoldingDrop = false
local bagObject = nil
local heldDrop = nil
CurrentDrop = nil

-- Fetch existing ground drops on spawn / resource start
function GetDrops()
    TMGCore.Functions.TriggerCallback('tmg-inventory:server:GetCurrentDrops', function(drops)
        if not drops then return end
        for k, v in pairs(drops) do
            local bag = NetworkGetEntityFromNetworkId(v.entityId)
            if DoesEntityExist(bag) then
                exports['tmg-target']:AddTargetEntity(bag, {
                    options = {
                        {
                            icon = 'fas fa-backpack',
                            label = Lang:t('menu.o_bag'),
                            action = function()
                                TriggerServerEvent('tmg-inventory:server:openDrop', k)
                                CurrentDrop = k
                            end,
                        },
                    },
                    distance = 2.5,
                })
            end
        end
    end)
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    GetDrops()
end)

RegisterNetEvent('TMGCore:Client:OnPlayerLoaded', function()
    GetDrops()
end)

RegisterNetEvent('tmg-inventory:client:removeDropTarget', function(netId)
    while not NetworkDoesNetworkIdExist(netId) do Wait(10) end
    local bag = NetworkGetEntityFromNetworkId(netId)
    while not DoesEntityExist(bag) do Wait(10) end
    exports['tmg-target']:RemoveTargetEntity(bag)
end)

RegisterNetEvent('tmg-inventory:client:setupDropTarget', function(netId)
    while not NetworkDoesNetworkIdExist(netId) do Wait(10) end
    local bag = NetworkGetEntityFromNetworkId(netId)
    while not DoesEntityExist(bag) do Wait(10) end
    local newDropId = 'drop-' .. netId

    exports['tmg-target']:AddTargetEntity(bag, {
        options = {
            {
                icon = 'fas fa-backpack',
                label = Lang:t('menu.o_bag'),
                action = function()
                    TriggerServerEvent('tmg-inventory:server:openDrop', newDropId)
                    CurrentDrop = newDropId
                end,
            },
            {
                icon = 'fas fa-hand-pointer',
                label = 'Pick up bag',
                action = function()
                    if IsPedArmed(PlayerPedId(), 4) then
                        return TMGCore.Functions.Notify("You cannot be holding a Gun and a Bag!", "error", 5500)
                    end
                    if HoldingDrop then
                        return TMGCore.Functions.Notify("You are already holding a bag, go drop it!", "error", 5500)
                    end

                    AttachEntityToEntity(
                        bag,
                        PlayerPedId(),
                        GetPedBoneIndex(PlayerPedId(), Config.ItemDropObjectBone or 28422),
                        Config.ItemDropObjectOffset[1].x,
                        Config.ItemDropObjectOffset[1].y,
                        Config.ItemDropObjectOffset[1].z,
                        Config.ItemDropObjectOffset[2].x,
                        Config.ItemDropObjectOffset[2].y,
                        Config.ItemDropObjectOffset[2].z,
                        true, true, false, true, 1, true
                    )
                    bagObject = bag
                    HoldingDrop = true
                    heldDrop = newDropId
                    exports['tmg-core']:DrawText('Press [G] to drop the bag')
                end,
            }
        },
        distance = 2.5,
    })
end)

-- Handle NUI Callback (Supports both dropItem and DropItem)
local function handleDropItem(item, cb)
    TMGCore.Functions.TriggerCallback('tmg-inventory:server:createDrop', function(netId)
        if netId then
            while not NetworkDoesNetworkIdExist(netId) do Wait(10) end
            local bag = NetworkGetEntityFromNetworkId(netId)
            SetModelAsNoLongerNeeded(bag)
            PlaceObjectOnGroundProperly(bag)
            FreezeEntityPosition(bag, true)
            local newDropId = 'drop-' .. netId
            cb(newDropId)
        else
            cb(false)
        end
    end, item)
end

RegisterNUICallback('dropItem', handleDropItem)
RegisterNUICallback('DropItem', handleDropItem)

-- Thread to place carried bag on ground when pressing [G]
CreateThread(function()
    while true do
        if HoldingDrop then
            if IsControlJustPressed(0, 47) then -- Control 47 = [G]
                DetachEntity(bagObject, true, true)
                local coords = GetEntityCoords(PlayerPedId())
                local forward = GetEntityForwardVector(PlayerPedId())
                local x, y, z = table.unpack(coords + forward * 0.57)

                SetEntityCoords(bagObject, x, y, z - 0.9, false, false, false, false)
                FreezeEntityPosition(bagObject, true)
                exports['tmg-core']:HideText()

                TriggerServerEvent('tmg-inventory:server:updateDrop', heldDrop, vector3(x, y, z - 0.9))

                HoldingDrop = false
                bagObject = nil
                heldDrop = nil
            end
        end
        Wait(0)
    end
end)