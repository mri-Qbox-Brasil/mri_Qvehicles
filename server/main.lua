-- Cadastro de veiculos em runtime e estoque. O qbx_core continua dono da lista
-- (API em qbx_core/mri/server/vehicles.lua); aqui fica a tabela vehicles_data:
--   name/brand/price/category/type: NULL = valor do shared/vehicles.lua, preenchido = editado
--   removed: carro do jogo removido pelo painel
--   stock: estoque da concessionaria (exports GetStock/TakeStock/ReturnStock)
-- As mudancas sao reaplicadas no qbx_core no start deste resource e do qbx_core.

local ADMIN_ACE = 'mri_Qvehicles.admin'

local FIELDS = { 'name', 'brand', 'price', 'category', 'type' }

---Lista original do shared/vehicles.lua: base pra saber o que foi editado e pra restaurar.
---@type table<string, Vehicle>
local baseVehicles = require '@qbx_core.shared.vehicles'

---@class VehicleRow
---@field fields table campos editados (so os diferentes do shared/vehicles.lua)
---@field removed boolean
---@field stock integer

---@type table<string, VehicleRow>
local rows = {}

local loaded = false

---@param source integer
---@return boolean
local function isAdmin(source)
    if source == 0 then return true end
    return IsPlayerAceAllowed(source, ADMIN_ACE) or IsPlayerAceAllowed(source, 'command')
end

---@param model string
---@return VehicleRow
local function getRow(model)
    local row = rows[model]
    if not row then
        row = { fields = {}, removed = false, stock = 0 }
        rows[model] = row
    end
    return row
end

---@param vehicle table
---@return table
local function pickFields(vehicle)
    local data = {}
    for i = 1, #FIELDS do
        data[FIELDS[i]] = vehicle[FIELDS[i]]
    end
    return data
end

---Grava a linha inteira. Campo nil vira NULL (o oxmysql nao aceita nil no meio dos parametros).
---@param model string
local function saveRow(model)
    local row = rows[model]
    local columns = { 'model', 'stock', 'removed' }
    local values = { '?', '?', '?' }
    local params = { model, row.stock, row.removed and 1 or 0 }

    for i = 1, #FIELDS do
        local field = FIELDS[i]
        columns[#columns + 1] = ('`%s`'):format(field)
        if row.fields[field] == nil then
            values[#values + 1] = 'NULL'
        else
            values[#values + 1] = '?'
            params[#params + 1] = row.fields[field]
        end
    end

    local updates = {}
    for i = 2, #columns do
        updates[#updates + 1] = ('%s = VALUES(%s)'):format(columns[i], columns[i])
    end

    MySQL.query.await(('INSERT INTO vehicles_data (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s'):format(
        table.concat(columns, ', '), table.concat(values, ', '), table.concat(updates, ', ')
    ), params)
end

---@param model string
local function deleteRow(model)
    rows[model] = nil
    MySQL.query.await('DELETE FROM vehicles_data WHERE model = ?', { model })
end

---Aplica a linha no qbx_core.
---@param model string
local function applyRow(model)
    local row = rows[model]
    if row.removed then
        exports.qbx_core:RemoveVehicleData(model)
        return
    end
    if not next(row.fields) then return end

    local ok, err = exports.qbx_core:UpsertVehicleData(model, row.fields)
    if not ok then
        lib.print.warn(('[mri_Qvehicles] %s nao foi aplicado: %s'):format(model, err))
    end
end

local function applyAll()
    local ok, err = pcall(function()
        for model in pairs(rows) do
            applyRow(model)
        end
    end)
    if not ok then
        lib.print.error(('[mri_Qvehicles] qbx_core sem a API de veiculos (UpsertVehicleData): %s'):format(err))
    end
end

---@param column string
---@return table?
local function getColumn(column)
    return MySQL.single.await([[
        SELECT IS_NULLABLE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'vehicles_data' AND COLUMN_NAME = ?
    ]], { column })
end

---Cria a tabela ou ajusta a que o qbx_vehicleshop criava (copia completa de cada carro).
local function prepareSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `vehicles_data` (
            `model` VARCHAR(50) NOT NULL,
            `stock` INT NOT NULL DEFAULT 0,
            `price` INT DEFAULT NULL,
            `name` VARCHAR(100) DEFAULT NULL,
            `brand` VARCHAR(50) DEFAULT NULL,
            `category` VARCHAR(50) DEFAULT NULL,
            `hash` BIGINT DEFAULT NULL,
            `type` VARCHAR(20) DEFAULT NULL,
            `removed` TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (`model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    if not getColumn('type') then
        MySQL.query.await('ALTER TABLE `vehicles_data` ADD COLUMN `type` VARCHAR(20) DEFAULT NULL')
    end
    if not getColumn('removed') then
        MySQL.query.await('ALTER TABLE `vehicles_data` ADD COLUMN `removed` TINYINT(1) NOT NULL DEFAULT 0')
    end

    -- A versao antiga do qbx_vehicleshop criava price NOT NULL; NULL agora significa "valor original".
    local price = getColumn('price')
    if price and price.IS_NULLABLE == 'NO' then
        MySQL.query.await('ALTER TABLE `vehicles_data` MODIFY `price` INT DEFAULT NULL')
    end
end

---Carrega a tabela. Campo igual ao shared/vehicles.lua vira NULL (a versao antiga do
---qbx_vehicleshop gravava uma copia completa de cada carro).
local function loadRows()
    local normalized, orphans = 0, 0

    for _, data in ipairs(MySQL.query.await('SELECT * FROM vehicles_data') or {}) do
        local model = data.model
        local base = baseVehicles[model]
        local row = {
            fields = {},
            removed = data.removed == 1 or data.removed == true,
            stock = tonumber(data.stock) or 0,
        }

        local changed = false
        for i = 1, #FIELDS do
            local field = FIELDS[i]
            local value = data[field]
            if value ~= nil then
                if base and base[field] == value then
                    changed = true
                else
                    row.fields[field] = value
                end
            end
        end

        rows[model] = row

        if changed then
            normalized += 1
            saveRow(model)
        end

        -- Carro que nao existe no shared/vehicles.lua e sem tipo: sobra de uma copia antiga
        if not base and next(row.fields) and not row.fields.type then
            orphans += 1
            row.fields = {}
            saveRow(model)
        end
    end

    return normalized, orphans
end

CreateThread(function()
    prepareSchema()
    local normalized, orphans = loadRows()
    applyAll()
    loaded = true

    local changed = 0
    for _, row in pairs(rows) do
        if row.removed or next(row.fields) then changed += 1 end
    end

    lib.print.info(('[mri_Qvehicles] %s veiculos alterados aplicados no qbx_core'):format(changed))
    if normalized > 0 then
        lib.print.info(('[mri_Qvehicles] %s linhas da vehicles_data ajustadas para o formato novo'):format(normalized))
    end
    if orphans > 0 then
        lib.print.warn(('[mri_Qvehicles] %s linhas sem tipo e fora do shared/vehicles.lua foram ignoradas'):format(orphans))
    end
end)

-- qbx_core reiniciou: a lista voltou ao shared/vehicles.lua, reaplica as mudancas.
AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName == 'qbx_core' and loaded then
        applyAll()
    end
end)

-- Estoque ------------------------------------------------------------------

---@param model string
---@return integer
local function getStock(model)
    local row = rows[model]
    return row and row.stock or 0
end

exports('GetStock', getStock)

---Estoque de todos os modelos com linha na tabela (sem linha = 0).
---@return table<string, integer>
exports('GetStocks', function()
    local stocks = {}
    for model, row in pairs(rows) do
        stocks[model] = row.stock
    end
    return stocks
end)

---Tira uma unidade. Atomico no banco: duas compras simultaneas nao vendem o ultimo carro duas vezes.
---@param model string
---@return boolean
local function takeStock(model)
    local affected = MySQL.update.await('UPDATE vehicles_data SET stock = stock - 1 WHERE model = ? AND stock > 0', { model })
    if affected > 0 then
        local row = rows[model]
        if row then row.stock -= 1 end
        return true
    end
    return false
end

exports('TakeStock', takeStock)

---@param model string
local function returnStock(model)
    getRow(model).stock += 1
    saveRow(model)
end

exports('ReturnStock', returnStock)

---@param model string
---@param stock integer
local function setStock(model, stock)
    getRow(model).stock = math.max(0, math.floor(stock))
    saveRow(model)
end

exports('SetStock', setStock)

-- Painel ---------------------------------------------------------------------

---@param value any
---@return string?
local function cleanString(value)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    return value ~= '' and value or nil
end

lib.callback.register('mri_Qvehicles:server:getVehicles', function(source)
    if not isAdmin(source) then return { success = false, message = 'no_permission' } end
    while not loaded do Wait(100) end

    local list = {}
    for model, vehicle in pairs(exports.qbx_core:GetVehiclesByName()) do
        local row = rows[model]
        local vehicleData = pickFields(vehicle)
        vehicleData.model = model
        vehicleData.stock = getStock(model)
        vehicleData.status = not baseVehicles[model] and 'added'
            or (row and next(row.fields) and 'edited')
            or 'base'
        list[#list + 1] = vehicleData
    end

    for model, row in pairs(rows) do
        if row.removed and baseVehicles[model] then
            local vehicleData = pickFields(baseVehicles[model])
            vehicleData.model = model
            vehicleData.stock = row.stock
            vehicleData.status = 'removed'
            list[#list + 1] = vehicleData
        end
    end

    return { success = true, vehicles = list }
end)

lib.callback.register('mri_Qvehicles:server:saveVehicle', function(source, payload)
    if not isAdmin(source) then return { success = false, message = 'no_permission' } end
    if type(payload) ~= 'table' then return { success = false, message = 'invalid_data' } end

    local model = cleanString(payload.model)
    if not model then return { success = false, message = 'invalid_model' } end
    model = model:lower()

    if rows[model] and rows[model].removed then
        return { success = false, message = 'vehicle_removed' }
    end

    local price = tonumber(payload.price)
    local data = {
        name = cleanString(payload.name),
        brand = cleanString(payload.brand) or '',
        price = price and math.max(0, math.floor(price)) or nil,
        category = cleanString(payload.category) or '',
        type = cleanString(payload.type),
    }

    local base = baseVehicles[model]

    -- Carro do jogo recebe os valores completos (campo que voltou ao original tambem precisa voltar no core)
    local ok, err = exports.qbx_core:UpsertVehicleData(model, data)
    if not ok then return { success = false, message = err } end

    local row = getRow(model)
    row.fields = {}
    for i = 1, #FIELDS do
        local field = FIELDS[i]
        if data[field] ~= nil and not (base and base[field] == data[field]) then
            row.fields[field] = data[field]
        end
    end

    local stock = tonumber(payload.stock)
    if stock then row.stock = math.max(0, math.floor(stock)) end

    saveRow(model)
    return { success = true }
end)

lib.callback.register('mri_Qvehicles:server:removeVehicle', function(source, model)
    if not isAdmin(source) then return { success = false, message = 'no_permission' } end
    if type(model) ~= 'string' then return { success = false, message = 'invalid_model' } end

    local ok, err = exports.qbx_core:RemoveVehicleData(model)
    if not ok then return { success = false, message = err } end

    if baseVehicles[model] then
        local row = getRow(model)
        row.removed = true
        saveRow(model)
    else
        deleteRow(model)
    end

    return { success = true }
end)

lib.callback.register('mri_Qvehicles:server:restoreVehicle', function(source, model)
    if not isAdmin(source) then return { success = false, message = 'no_permission' } end
    local base = type(model) == 'string' and baseVehicles[model]
    if not base then return { success = false, message = 'not_base_vehicle' } end

    local ok, err = exports.qbx_core:UpsertVehicleData(model, pickFields(base))
    if not ok then return { success = false, message = err } end

    local row = getRow(model)
    row.fields = {}
    row.removed = false
    saveRow(model)

    return { success = true }
end)

-- Registro como plugin do mri_Qadmin, igual ao mri_Qspawn e mri_Qmultichar.
local function doRegister()
    if GetResourceState('mri_Qadmin') ~= 'started' then return end
    local ok, err = pcall(function()
        exports['mri_Qadmin']:RegisterPlugin({
            id = 'vehicles',
            label = 'Veículos',
            icon = 'car',
            resource = 'mri_Qvehicles',
            htmlPath = 'html/index.html',
            requiredPerms = { ADMIN_ACE, 'command' },
            description = 'Cadastro, edição e estoque de veículos sem reiniciar',
        })
    end)
    if not ok then
        lib.print.warn(('[mri_Qvehicles] Falha ao registrar plugin no mri_Qadmin: %s'):format(err))
    end
end

AddEventHandler('mri_Qadmin:server:pluginsReady', doRegister)

AddEventHandler('onServerResourceStart', function(resourceName)
    if resourceName == 'mri_Qadmin' then doRegister() end
end)

CreateThread(function()
    Wait(0)
    doRegister()
end)
