local ox_lib, msg_lib = lib.checkDependency('ox_lib', '3.24.0')
if not ox_lib then print(msg_lib) return end

if GetResourceState('ox_inventory') == 'started' then
    local ox_inv, msg_inv = lib.checkDependency('ox_inventory', '2.41.0')
    if not ox_inv then print(msg_inv) return end
end

---@class Handler : OxClass
local Handler = require 'modules.handler'
local Settings = lib.load('data.vehicle')
local vehicleData = {['engine'] = 0, ['body'] = 0, ['speed'] = 0}

local function startThread(vehicle)
    if not vehicle then return end
    if not Handler or Handler:isActive() then return end

    Handler:setActive(true)

    local oxfuel = Handler:isFuelOx()
    local units = Handler:getUnits()
    local class = Handler:getClass()

    CreateThread(function()
        while (cache.vehicle == vehicle) and (cache.seat == -1) do

            -- Retrieve latest vehicle data
            vehicleData['engine'] = GetVehicleEngineHealth(vehicle)
            vehicleData['body'] = GetVehicleBodyHealth(vehicle)
            vehicleData['speed'] = GetEntitySpeed(vehicle) * units

            -- Driveability handler (health, fuel)
            local fuel = oxfuel and Entity(vehicle).state.fuel or GetVehicleFuelLevel(vehicle)
            if vehicleData['engine'] <= 0 or fuel <= 6.4 then
                if IsVehicleDriveable(vehicle, true) then
                    SetVehicleUndriveable(vehicle, true)
                end
            end

            -- Reduce torque after half-life
            if vehicleData['engine'] < 500 then
                if not Handler:isLimited() then
                    Handler:setLimited(true)

                    CreateThread(function()
                        while (cache.vehicle == vehicle) and (cache.seat == -1) and (vehicleData['engine'] < 500) do
                            local newtorque = (vehicleData['engine'] + 500) / 1100
                            SetVehicleCheatPowerIncrease(vehicle, newtorque)
                            Wait(1)
                        end

                        Handler:setLimited(false)
                    end)
                end
            end

            -- Prevent rotation controls while flipped/airborne
            if Settings.regulated[class] then
                local roll, airborne = 0.0, false

                if vehicleData['speed'] < 2.0 then
                    roll = GetEntityRoll(vehicle)
                else
                    airborne = IsEntityInAir(vehicle)
                end

                if (roll > 75.0 or roll < -75.0) or airborne then
                    if Handler:canControl() then
                        Handler:setControl(false)

                        CreateThread(function()
                            while not Handler:canControl() and cache.seat == -1 do
                                DisableControlAction(2, 59, true) -- Disable left/right
                                DisableControlAction(2, 60, true) -- Disable up/down
                                Wait(1)
                            end

                            if not Handler:canControl() then Handler:setControl(true) end
                        end)
                    end
                else
                    if not Handler:canControl() then Handler:setControl(true) end
                end
            end

            Wait(200)
        end

        vehicleData = {['engine'] = 0, ['body'] = 0, ['speed'] = 0}
        Handler:setActive(false)

        -- Retrigger thread if admin spawns a new vehicle while in one
        if cache.vehicle and cache.seat == -1 then
            startThread(cache.vehicle)
        end
    end)
end

AddEventHandler('entityDamaged', function (victim, _, weapon, _)
    if not Handler or not Handler:isActive() then return end
    if victim ~= cache.vehicle then return end
    if GetWeapontypeGroup(weapon) ~= 0 then return end

    -- Damage handler
    local bodyDiff = vehicleData['body'] - GetVehicleBodyHealth(cache.vehicle)
    if bodyDiff >= 1 then

        -- Calculate latest damage
        local bodyDamage = bodyDiff * Settings.globalmultiplier * Settings.classmultiplier[Handler:getClass()]
        local newEngine = vehicleData['engine'] - bodyDamage

        -- Update engine health
        if newEngine ~= vehicleData['engine'] and newEngine > 0 then
            SetVehicleEngineHealth(cache.vehicle, newEngine)
        elseif newEngine ~= 0 then
            SetVehicleEngineHealth(cache.vehicle, 0.0) -- prevent negative engine health
        end

        -- Prevent negative body health
        if vehicleData['body'] < 0 then
            SetVehicleBodyHealth(cache.vehicle, 0.0)
        end

        -- Prevent negative tank health (explosion)
        if GetVehiclePetrolTankHealth(cache.vehicle) < 0 then
            SetVehiclePetrolTankHealth(cache.vehicle, 0.0)
        end
    end

    -- Impact handler
    local speedDiff = vehicleData['speed'] - (GetEntitySpeed(cache.vehicle) *  Handler:getUnits())
    if speedDiff >= Settings.threshold.speed then

        -- Handle wheel loss
        if Settings.breaktire then
            if bodyDiff >= Settings.threshold.tire then
                math.randomseed(GetGameTimer())
                Handler:breakTire(cache.vehicle, math.random(0, 1))
            end
        end

        -- Handle heavy impact
        if speedDiff >= Settings.threshold.heavy then
            SetVehicleUndriveable(cache.vehicle, true)
            SetVehicleEngineHealth(cache.vehicle, 0.0) -- Disable vehicle completely
        end
    end
end)

lib.callback.register('vehiclehandler:basicfix', function(fixtype)
    if not Handler then return end
    return Handler:basicfix(fixtype)
end)

lib.callback.register('vehiclehandler:basicwash', function()
    if not Handler then return end
    return Handler:basicwash()
end)

lib.callback.register('vehiclehandler:adminfix', function()
    if not Handler or not Handler:isActive() then return end
    return Handler:adminfix()
end)

lib.callback.register('vehiclehandler:adminwash', function()
    if not Handler or not Handler:isActive() then return end
    return Handler:adminwash()
end)

lib.callback.register('vehiclehandler:adminfuel', function(newlevel)
    if not Handler or not Handler:isActive() then return end
    return Handler:adminfuel(newlevel)
end)

lib.onCache('seat', function(seat)
    if seat == -1 then
        startThread(cache.vehicle)
    end
end)

CreateThread(function()
    Handler = Handler:new()

    if cache.seat == -1 then
        startThread(cache.vehicle)
    end
end)