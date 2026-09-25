-- Ponte entre o painel (embutido no mri_Qadmin) e o servidor. A permissao e
-- checada no servidor em cada callback.

RegisterNUICallback('getVehicles', function(_, cb)
    local result = lib.callback.await('mri_Qvehicles:server:getVehicles', false)
    if result and result.vehicles then
        -- Modelo sem arquivo no jogo: pack do carro nao esta rodando ou nome errado.
        for i = 1, #result.vehicles do
            local vehicle = result.vehicles[i]
            vehicle.inGame = IsModelInCdimage(joaat(vehicle.model))
        end
    end
    cb(result or { success = false })
end)

RegisterNUICallback('saveVehicle', function(data, cb)
    cb(lib.callback.await('mri_Qvehicles:server:saveVehicle', false, data) or { success = false })
end)

RegisterNUICallback('removeVehicle', function(data, cb)
    cb(lib.callback.await('mri_Qvehicles:server:removeVehicle', false, data.model) or { success = false })
end)

RegisterNUICallback('restoreVehicle', function(data, cb)
    cb(lib.callback.await('mri_Qvehicles:server:restoreVehicle', false, data.model) or { success = false })
end)

-- Um veiculo ou o estoque mudou: avisa a pagina NUI deste resource, que repassa pro
-- painel aberto no mri_Qadmin (web/src/App.tsx).
RegisterNetEvent('mri_Qvehicles:client:changed', function()
    SendNUIMessage({ action = 'changed' })
end)

RegisterNUICallback('checkModel', function(data, cb)
    cb({ inGame = type(data.model) == 'string' and IsModelInCdimage(joaat(data.model)) or false })
end)
