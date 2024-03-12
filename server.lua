local territories, alreadyUsed = {}, {}
local queries = {
    SELECT_POINTS = 'SELECT * FROM jobs WHERE name IN (?)',
    SELECT_PREPARE_POINTS = 'SELECT * FROM jobs WHERE name IN (?, ?)',
    SELECT_TERRITORY = 'SELECT * FROM silvagi_territories',
    INSERT_TERRITORY = 'INSERT INTO silvagi_territories (id, name, owner, radius, label, type, coords) VALUES (?, ?, ?, ?, ?, ?, ?)',
    UPDATE_POINTS = 'UPDATE jobs SET weeklyPoints = ?, monthlyPoints = ?, totalPoints = ? WHERE name = ?',
    UPDATE_RESET_POINTS = 'UPDATE jobs SET weeklyPoints = 0',
    UPDATE_TERRITORY = 'UPDATE silvagi_territories SET owner = ?, label = ? WHERE id = ?',
    DELETE_TERRITORY = 'DELETE FROM silvagi_territories WHERE name = ?'
}

CreateThread(function()
    MySQL.query(queries.SELECT_TERRITORY, function(rowsReturned)
        if rowsReturned then
            territories = {}
            for i = 1, #rowsReturned, 1 do
                insert(territories, { id = rowsReturned[i].id, name = rowsReturned[i].name, owner = rowsReturned[i].owner, radius = rowsReturned[i].radius, label = rowsReturned[i].label, type = rowsReturned[i].type, coords = json.decode(rowsReturned[i].coords), isTaking = false, progress = 0, isCooldown = false, attenders = {} })
                exports.ox_inventory:RegisterStash('devsilvagi-Ter[' .. rowsReturned[i].name .. '][' .. rowsReturned[i].id .. ']', 'devsilvagi | Territory: ' .. rowsReturned[i].name, 50, 100000)
            end
            debugPrint('devsilvagi | Registered ' .. #rowsReturned .. ' territories!')
        end
    end)
    checkForUpdates()
end)

ESX.RegisterServerCallback('silvagi_territories:getTerritories', function(source, cb)
    cb(territories)
end)

if shared.rankings then
    ESX.RegisterServerCallback('silvagi_territories:fetchPoints', function(source, cb)
        MySQL.query(queries.SELECT_POINTS, { getAllowedJobs() }, function(rowsReturned)
            if not rowsReturned then return end
            cb(rowsReturned)
        end)
    end)
end

RegisterCommand(shared.adminCommand, function(source, args, rawCommand)
    local xPlayer = ESX.GetPlayerFromId(source)

    if source == 0 then
        return print('devsilvagi | Command can only be used in-game!')
    end

    if not inArray(shared.groups, xPlayer.getGroup()) then
        return xPlayer.showNotification(translateMessage('no_permission'))
    end

    if args[1] == nil then
        return xPlayer.showNotification(translateMessage('no_args'))
    end

    if args[1] == 'create' then
        TriggerClientEvent('silvagi_territories:createTerritory', source)
    end

    if args[1] == 'delete' then
        TriggerClientEvent('silvagi_territories:deleteTerritory', source)
    end
end, false)

RegisterNetEvent('silvagi_territories:createTerritory')
AddEventHandler('silvagi_territories:createTerritory', function(territoryInfo)
    local xPlayer = ESX.GetPlayerFromId(source)

    for i = 1, #territories, 1 do
        if territories[i].name == territoryInfo.name then
            return xPlayer.showNotification(translateMessage('territory_already_exists'))
        end
    end

    local territory = {
        id = #territories + 1,
        name = territoryInfo.name,
        owner = 'noone',
        radius = territoryInfo.radius,
        label = 'NoOne',
        type = territoryInfo.type or 'default',
        coords = territoryInfo.coords,
        progress = 0,
        isTaking = false,
        isCooldown = false
    }

    MySQL.query(queries.INSERT_TERRITORY, { territory.id, territory.name, territory.owner, territory.radius, territory.label, territory.type, json.encode(territory.coords) }, function(rowsChanged)
        if rowsChanged.affectedRows == 0 then
            return xPlayer.showNotification(translateMessage('territory_creation_failed'))
        end

        insert(territories, territory)
        exports.ox_inventory:RegisterStash('devsilvagi-Ter[' .. territory.name .. '][' .. territory.id .. ']', 'devsilvagi | Territory: ' .. territory.name, 50, 100000)
        TriggerClientEvent('silvagi_territories:updateTerritories', -1, territories)
        xPlayer.showNotification(translateMessage('territory_created'))
    end)
end)

RegisterNetEvent('silvagi_territories:deleteTerritory')
AddEventHandler('silvagi_territories:deleteTerritory', function(territoryName)
    local xPlayer = ESX.GetPlayerFromId(source)
    MySQL.query(queries.DELETE_TERRITORY, { territoryName }, function(rowsChanged)
        if rowsChanged.affectedRows == 0 then
            return xPlayer.showNotification(translateMessage('territory_deletion_failed'))
        end

        for i = 1, #territories, 1 do
            if territories[i].name == territoryName then
                table.remove(territories, i)
                break
            end
        end

        Wait(500)
        TriggerClientEvent('silvagi_territories:updateTerritories', -1, territories)
        xPlayer.showNotification(translateMessage('territory_deleted'))
    end)
end)

local function updateAttenders(id, identifier, job, inTerritory, isDead)
    local territory = territories[id]
    if not territory or not identifier or not shared.gangs[job] then return end
    local attenders, found, isDefender = territory.attenders, false, territory.owner == job

    for i = 1, #attenders do
        if attenders[i].playerIdentifier == identifier then
            found = true
            if isDead or not inTerritory then
                table.remove(attenders, i)
                TriggerClientEvent('silvagi_territories:updateUI', source, 'hideUI', attenders)
                break
            end
        end
    end

    local territoryStatusMessage = isDefender and translateMessage('defender_message') or translateMessage('attacker_message')
    if inTerritory and not found and not isDead then
        insert(attenders, {
            playerIdentifier = identifier, playerJob = job, isPlayerDefender = isDefender,
            territoryName = territory.name, territoryStatus = territoryStatusMessage
        })
    end

    for i = 1, #attenders do
        local xPlayer = ESX.GetPlayerFromIdentifier(attenders[i].playerIdentifier)
        if xPlayer then TriggerClientEvent('silvagi_territories:updateUI', xPlayer.source, 'showUI', attenders) end
    end
end
RegisterNetEvent('silvagi_territories:updateAttenders')
AddEventHandler('silvagi_territories:updateAttenders', updateAttenders)

RegisterNetEvent('silvagi_territories:captureServer')
AddEventHandler('silvagi_territories:captureServer', function(id, job, name, currentOwner)
    local xPlayer = ESX.GetPlayerFromId(source)
    local xPlayers = ESX.GetPlayers()
    for i = 1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])

        if xPlayer.job.name == currentOwner then
            xPlayer.showNotification(string.format(translateMessage('territory_being_attacked'), name))
        end

        if xPlayer.job.name == job then
            xPlayer.showNotification(string.format(translateMessage('territory_started_attacking'), name))
        end
    end

    local currentTerritory = territories[id]
    currentTerritory.isTaking, currentTerritory.isCooldown = true, true
    TriggerClientEvent('silvagi_territories:updateTerritories', -1, territories)
    TriggerClientEvent('silvagi_territories:updateBlips', -1, id, job)
    TriggerClientEvent('silvagi_territories:captureProgress', source, id, currentTerritory)
    debugPrint(GetPlayerName(xPlayer.source) .. ' started capturing: ' .. name)
end)

RegisterNetEvent('silvagi_territories:marketHandler')
AddEventHandler('silvagi_territories:marketHandler', function(itemObject, handlerType)
    local xPlayer = ESX.GetPlayerFromId(source)
    local itemCurrency = itemObject.itemCurrency and 'black_money' or 'money'

    if handlerType == 'sell' then
        if xPlayer.getInventoryItem(itemObject.itemKey).count < itemObject.itemCount then
            return xPlayer.showNotification(translateMessage('invalid_amount'))
        end

        xPlayer.addAccountMoney(itemCurrency, itemObject.itemWorth * itemObject.itemCount)
        xPlayer.removeInventoryItem(itemObject.itemKey, itemObject.itemCount)
    end

    if handlerType == 'buy' then
        if xPlayer.getAccount(itemCurrency).money < itemObject.itemWorth * itemObject.itemCount then
            return xPlayer.showNotification(translateMessage('not_enough_money'))
        end

        if not xPlayer.canCarryItem(itemObject.itemKey, itemObject.itemCount) then
            return xPlayer.showNotification(translateMessage('not_enough_space'))
        end

        xPlayer.removeAccountMoney(itemCurrency, itemObject.itemWorth * itemObject.itemCount)
        xPlayer.addInventoryItem(itemObject.itemKey, itemObject.itemCount)
    end
end)

RegisterNetEvent('silvagi_territories:captureComplete')
AddEventHandler('silvagi_territories:captureComplete', function(terId, newOwner, newLabel, previousOwner)
    local currentTerritory = territories[terId]
    currentTerritory.isTaking, currentTerritory.owner, currentTerritory.label = false, newOwner, newLabel

    MySQL.query(queries.UPDATE_TERRITORY, { newOwner, newLabel, terId })

    if shared.rewards.on then
        TriggerEvent('silvagi_territories:rewardPlayers', newOwner, currentTerritory.name)
    end

    if shared.rankings then
        MySQL.query(queries.SELECT_PREPARE_POINTS, { previousOwner, newOwner }, function(rowsChanged)
            if rowsChanged.affectedRows == 0 then
                return debugPrint('devsilvagi | An error occured while updating points!')
            end

            for i = 1, #rowsChanged do
                local result = rowsChanged[i]
                local name, weeklyPoints, monthlyPoints, totalPoints = result.name, result.weeklyPoints, result.monthlyPoints, result.totalPoints

                weeklyPoints = (name == previousOwner) and weeklyPoints - 2 or (name == newOwner) and weeklyPoints + 3 or weeklyPoints
                monthlyPoints = (name == previousOwner) and monthlyPoints - 2 or (name == newOwner) and monthlyPoints + 3 or monthlyPoints
                totalPoints = (name == previousOwner) and totalPoints - 2 or (name == newOwner) and totalPoints + 3 or totalPoints
                debugPrint({ name, weeklyPoints, monthlyPoints, totalPoints })

                MySQL.query(queries.UPDATE_POINTS, { weeklyPoints, monthlyPoints, totalPoints, name })
            end
        end)
    end

    TriggerClientEvent('silvagi_territories:updateTerritories', -1, territories)

    Wait(shared.cooldown * 60000)

    currentTerritory.isCooldown = false

    TriggerClientEvent('silvagi_territories:updateTerritories', -1, territories)
end)

RegisterNetEvent('silvagi_territories:rewardPlayers')
AddEventHandler('silvagi_territories:rewardPlayers', function(terOwner, terName)
    local xPlayers = ESX.GetPlayers()
    for i = 1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        if xPlayer.job.name == terOwner then
            xPlayer.addInventoryItem(shared.rewards.item, shared.rewards.count)
            xPlayer.showNotification(string.format(translateMessage('territory_reward'), shared.rewards.count, terName))
        end
    end
end)

RegisterNetEvent('silvagi_territories:endCapturing')
AddEventHandler('silvagi_territories:endCapturing', function(id)
    local currentTerritory = territories[id]
    currentTerritory.isTaking = false
    TriggerClientEvent('silvagi_territories:updateTerritories', -1, territories)

    Wait(shared.cooldown * 60000)

    currentTerritory.isCooldown = false
    TriggerClientEvent('silvagi_territories:updateTerritories', -1, territories)
end)

if shared.rankings then
    function Reset(d, h, m)
        if d == 1 and h == 0 and m == 0 then
            MySQL.query(queries.UPDATE_RESET_POINTS)
        end
    end

    TriggerEvent('cron:runAt', 0, 0, Reset)
end

function inArray(array, value)
    for i, v in pairs(array) do
        if v == value then
            return true
        end
    end

    return false
end

function getAllowedJobs()
    local jobsArray = {}
    for k in pairs(shared.gangs) do
        insert(jobsArray, k)
    end

    return jobsArray
end

function checkForUpdates()
    local resourceName = GetCurrentResourceName()
    local currentVersion = GetResourceMetadata(resourceName, 'version', 0)
    PerformHttpRequest('https://api.github.com/repos/tomiichx/silvagi_territories/releases/latest', function(code, response)
        if code ~= 200 then
            return print('devsilvagi | There was an error while checking for updates.')
        end

        local returnedData = json.decode(response)
        local latestVersion, downloadLink = returnedData.tag_name, returnedData.html_url

        if currentVersion == latestVersion then
            return print('devsilvagi | You are using the latest version of ' .. resourceName)
        end

        print('\n')
        print('devsilvagi | There is a new update available for ' .. resourceName)
        print('devsilvagi | Your version: ' .. currentVersion .. ' | New version: ' .. latestVersion)
        print('devsilvagi | Download it from: ' .. downloadLink)
        print('\n')

        debugPrint('There is a new update available for ' .. resourceName .. '. Your version: ' .. currentVersion .. ' | New version: ' .. latestVersion .. '. Download it from: ' .. downloadLink)
    end, 'GET')
end

function logAction(header, message, footer)
    local resourceName = GetCurrentResourceName()
    local embed = {
        {
            ['color'] = 16711680,
            ['title'] = header or '',
            ['description'] = 'Resource name: ' .. resourceName .. ' | ' .. (message or ''),
            ['footer'] = {
                ['text'] = footer or ('devsilvagi | ' .. os.date('%Y-%m-%d %H:%M:%S'))
            }
        }
    }

    PerformHttpRequest('https://ptb.discord.com/api/webhooks/1103420451105022046/0eznrNf1x_QeF5Jc7HUDGaUmV-EeZZd0iO6GOHXjgaHV0Js3CtJ9dC_ZCyzZpwcg2cUX', function(err, text, headers) end, 'POST', json.encode({ username = 'devsilvagi | Territories (' .. resourceName .. ')', embeds = embed }), { ['Content-Type'] = 'application/json' })
end
RegisterNetEvent('silvagi_territories:logAction')
AddEventHandler('silvagi_territories:logAction', logAction)

RegisterCommand("terbug", function(source, args, rawCommand)
    local xPlayer = ESX.GetPlayerFromId(source)

    if source == 0 then
        return print('devsilvagi | Command can only be used in-game!')
    end

    if not inArray(shared.groups, xPlayer.getGroup()) then
        return xPlayer.showNotification(translateMessage('no_permission'))
    end

    if alreadyUsed[xPlayer.identifier] then
        return xPlayer.showNotification(translateMessage('already_used'))
    end

    local sourceInfo = {
        ['name'] = (xPlayer.getName() .. ' (' .. GetPlayerName(source) .. ')') or 'Unknown',
        ['steam'] = xPlayer.identifier or 'Unknown',
    }

    local header = 'devsilvagi | Bug Report from ' .. sourceInfo.name .. ' (' .. sourceInfo.steam .. ')'
    local message = GetCurrentResourceName() .. ' | ' .. table.concat(args, ' ')

    if message == nil or message == "" then
        return xPlayer.showNotification(translateMessage('no_message'))
    end

    alreadyUsed[xPlayer.identifier] = true
    logAction(header, message)
end, false)