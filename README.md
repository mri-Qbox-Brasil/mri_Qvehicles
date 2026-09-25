# mri_Qvehicles

Cadastro, edição e estoque de veículos em tempo real, sem editar o `shared/vehicles.lua` do qbx_core e sem reiniciar o servidor. Funciona como aba do **mri_Qadmin**.

## Principais recursos

- **Adicionar veículos** (carros addon) direto pelo painel, com nome, marca, preço, categoria, tipo e estoque.
- **Editar veículos do jogo**: só os campos alterados ficam salvos. O resto continua vindo do `shared/vehicles.lua`, então atualizações do Qbox continuam chegando.
- **Remover e restaurar**: um veículo do jogo removido fica no filtro "Removidos" e volta ao original com um clique.
- **Estoque da concessionária** controlado pelo painel.
- **Aviso de modelo ausente**: o painel marca veículos cujo modelo não existe no jogo (nome errado ou pack do carro parado).
- Tudo vale na hora: concessionária, garagem, painel admin e demais scripts que usam a lista do qbx_core.

## Dependências

- `qbx_core` com a API de veículos em runtime (`UpsertVehicleData` e `RemoveVehicleData`, na pasta `mri/` do fork MRI).
- `ox_lib`
- `oxmysql`
- `mri_Qadmin` (o painel é uma aba dele)

## Instalação

1. Coloque a pasta `mri_Qvehicles` em `resources/`.
2. Adicione `ensure mri_Qvehicles` no `server.cfg`, depois do `qbx_core`.
3. Pronto: a tabela `vehicles_data` é criada ou ajustada sozinha no primeiro start.

### Vindo de uma base com a `vehicles_data` antiga

A versão antiga do `qbx_vehicleshop` gravava uma cópia completa de cada veículo nessa tabela. No primeiro start, o mri_Qvehicles:

- mantém o **estoque** de cada veículo;
- troca por `NULL` os campos iguais ao `shared/vehicles.lua` (passam a seguir o original);
- mantém como edição os campos diferentes (por exemplo, preços alterados pelo antigo `/setstock`).

Nada é apagado.

## Permissões

O painel aparece para quem tem `mri_Qvehicles.admin` ou `command`:

```
add_ace group.admin mri_Qvehicles.admin allow
```

## Tabela `vehicles_data`

| Coluna | Significado |
|---|---|
| `model` | nome de spawn do veículo |
| `stock` | estoque da concessionária |
| `name`, `brand`, `price`, `category`, `type` | `NULL` = valor do `shared/vehicles.lua`; preenchido = editado pelo painel |
| `removed` | veículo do jogo removido pelo painel |

## Exports (server)

| Export | Descrição |
|---|---|
| `GetStock(model)` | Estoque do modelo (0 quando não há linha). |
| `GetStocks()` | Estoque de todos os modelos com linha na tabela. |
| `TakeStock(model)` | Tira uma unidade. Retorna `false` sem estoque. Atômico no banco. |
| `ReturnStock(model)` | Devolve uma unidade (ex.: pagamento falhou). |
| `SetStock(model, stock)` | Define o estoque. |

O `qbx_vehicleshop` do MRI usa esses exports. Sem o mri_Qvehicles rodando, a concessionária funciona com estoque ilimitado.

## Para scripts que guardam a lista de veículos

Quem pega a lista uma vez (`exports.qbx_core:GetVehiclesByName()` ou `GetCoreObject().Shared.Vehicles`) recebe uma cópia. Para acompanhar as mudanças do painel, escute o evento do qbx_core:

```lua
-- server
AddEventHandler('qbx_core:server:onVehicleUpdate', function(model, vehicle)
    VEHICLES[model] = vehicle -- vehicle nil = removido
end)

-- client
RegisterNetEvent('qbx_core:client:onVehicleUpdate', function(model, vehicle)
    VEHICLES[model] = vehicle
end)
```

Quem chama o export na hora de usar já recebe a lista atualizada.

## Limitação

Cadastrar no painel não carrega o modelo 3D: o pack do carro precisa estar na pasta e rodando (`ensure` do pack, que pode ser feito sem reiniciar o servidor).
