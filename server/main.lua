ESX = nil
currentBanks = {}

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

function doDebitCardCheck()
    local toDelete = {}
    MySQL.Async.fetchAll("SELECT * FROM `debitcards`", {}, function(cards)
        if cards ~= nil then
            for k, v in pairs(cards) do
                local metaInfo = json.decode(v.cardmeta)
                if metaInfo.stolen then
                    local time = os.time(os.date("!*t"))
                    if time > metaInfo.stolenDelete then
                        toDelete[v.record_id] = v.owner_cid
                    end
                end
            end

            local deleted = 0
            for t, q in pairs(toDelete) do
                MySQL.Sync.execute("DELETE FROM `debitcards` WHERE `record_id` = @record", {['@record'] = t})
                deleted = deleted + 1
            end

            for x, y in pairs(toDelete) do
                local online = ESX.GetPlayerFromIdentifier(y)
                if online then
                    local DebitCards = {}
                    local DebitCards = MySQL.Sync.fetchAll("SELECT * FROM `debitcards` WHERE `owner_cid` = @cid", {['@cid'] = online.identifier})
                end
            end

            if deleted > 0 then
                print(' ^1[PixelWorld Banking] ^3- Deleted ^4'..deleted..'^3 Debit cards that have been reported stolen^7')
            end

            toDelete = nil
        end
    end)
    Citizen.SetTimeout(300000, doDebitCardCheck)
end

MySQL.ready(function ()
    MySQL.Async.fetchAll("SELECT * FROM `banks`", {}, function(banks)
        if banks ~= nil then
            for k, v in pairs(banks) do
                currentBanks[v.id] = { ['name'] = v.name, ['coords'] = json.decode(v.coords), ['bankOpen'] = v.bankOpen, ['bankCooldown'] = v.bankCooldown, ['bankType'] = v.bankType }
            end
        end
    end)
    Citizen.SetTimeout(10000, doDebitCardCheck)
end)

ESX.RegisterServerCallback('pw_banking:server:requestBanks', function(source, cb)
    cb(currentBanks)
end)

ChangePin = function(card, oldpin, newpin, cb)
    MySQL.Async.fetchAll("SELECT * FROM `debitcards` WHERE `record_id` = @card", {['@card'] = card}, function(cardinfo)
        if cardinfo[1] ~= nil then
            local metaDecode = json.decode(cardinfo[1].cardmeta)
            if not metaDecode.stolen then
                if metaDecode.cardPin == oldpin then
                    metaDecode.cardPin = newpin
                    MySQL.Async.execute("UPDATE `debitcards` SET `cardmeta` = @meta WHERE `record_id` = @card", {['@card'] = card, ['@meta'] = json.encode(metaDecode)}, function(done) end)
                end
            end
        end
    end)
end

RegisterServerEvent('pw_banking:server:changePin')
AddEventHandler('pw_banking:server:changePin', function(data)
    if data then
        local _src = source
        local _char = ESX.GetPlayerFromId(_src)
        if _char then
            ChangePin(tonumber(data.card), tonumber(data.oldPin), tonumber(data.newPin))
            TriggerClientEvent('pw_banking:client:externalChangePinMessage', _src, "success", "Your pin has been successfully changed.")
        end
    end
end)

RegisterServerEvent('pw_banking:server:quickTransfer')
AddEventHandler('pw_banking:server:quickTransfer', function(data)
    if data then
        local _src = source
        local _char = ESX.GetPlayerFromId(_src)
        local _currentBalance = _char.getAccount('bank').money
        local _savingsBalance = GetPlayerSavings(_src).balance
        local _cashBalance = _char.getMoney()
        if data.account == "current" then
            if data.type == "withdraw" then
                _char.removeAccountMoney('bank', tonumber(data.amount))
                _char.addMoney(tonumber(data.amount))
                AdjustStatement(_src, "withdraw", "personal", data.amount, "Bank Withdraw")
                TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
            else
                if _cashBalance > data.amount or _cashBalance == data.amount then
                    _char.removeMoney(tonumber(data.amount))
                    _char.addAccountMoney('bank', tonumber(data.amount))
                    AdjustStatement(_src, "deposit", "personal", data.amount, "Bank Deposit")
                    TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
                end
            end
        elseif data.account == "savings" then
            if data.type == "withdraw" then
                if _savingsBalance >= data.amount then
                    local Saving_Owner = GetPlayerSavings(_src).cid
                    RemoveSavingMoney(_src, tonumber(data.amount), Saving_Owner)
                    _char.addAccountMoney('bank', tonumber(data.amount))
                    AdjustStatement(_src, "withdraw", "savings", data.amount, "Savings Withdraw")
                    TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
                end
            else
                local Saving_Owner = GetPlayerSavings(_src).cid
                _char.addAccountMoney('bank', tonumber(data.amount))
                AddSavingMoney(_src, tonumber(data.amount), Saving_Owner)
                AdjustStatement(_src, "deposit", "savings", data.amount, "Savings Deposit")
                TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
            end
        else
        end
    end
end)

RemoveSavingMoney = function(source, amount, owner)
    local _src = source
    local old_balance = GetPlayerSavings(_src).balance
    local new_balance = old_balance - amount
    MySQL.Async.execute("UPDATE banking SET balance = @balance WHERE cid = @cid", {
        ['@balance'] = new_balance,
        ['@cid'] = owner
    }, function(rowsChanged) end)
end

AddSavingMoney = function(source, amount, owner)
    local _src = source
    local old_balance = GetPlayerSavings(_src).balance
    local new_balance = old_balance + amount
    MySQL.Async.execute("UPDATE banking SET balance = @balance WHERE cid = @cid", {
        ['@balance'] = new_balance,
        ['@cid'] = owner
    }, function(rowsChanged) end)
end

function GetPlayerCharacter(source)
    local xPlayer = ESX.GetPlayerFromId(source)
	local result = MySQL.Sync.fetchAll('SELECT * FROM users WHERE identifier = @identifier', {
		['@identifier'] = xPlayer.identifier
	})
    return result[1]
end

CheckPlayerSavings = function(source)
    local _src = source
    local xPlayer = ESX.GetPlayerFromId(_src)
    local result = MySQL.Sync.fetchAll('SELECT * FROM banking WHERE cid = @identifier', {
		['@identifier'] = xPlayer.identifier
	})
    if result[1] ~= nil then
        return true
    else
        return false
    end
end

CheckPlayerCard = function(source)
    local _src = source
    local xPlayer = ESX.GetPlayerFromId(_src)
    local result = MySQL.Sync.fetchAll('SELECT * FROM debitcards WHERE owner_cid = @identifier', {
		['@identifier'] = xPlayer.identifier
	})
    if result[1] ~= nil then
        return true
    else
        return false
    end
end

GetPlayerSavings = function(source)
    local _src = source
    local xPlayer = ESX.GetPlayerFromId(_src)
    local result = MySQL.Sync.fetchAll('SELECT * FROM banking WHERE cid = @identifier', {
		['@identifier'] = xPlayer.identifier
	})
    if result[1] ~= nil then
        return result[1]
    else
        return nil
    end
end

GetPlayerCards = function(source)
    local _src = source
    local xPlayer = ESX.GetPlayerFromId(_src)
    local result = MySQL.Sync.fetchAll('SELECT * FROM debitcards WHERE owner_cid = @identifier', {
		['@identifier'] = xPlayer.identifier
	})
    return result
end

GetPlayerStatement = function(source)
    local _src = source
    local xPlayer = ESX.GetPlayerFromId(_src)
    local result = MySQL.Sync.fetchAll('SELECT * FROM bank_statements WHERE `account` = @account AND `character_id` = @identifier', {
		['@identifier'] = xPlayer.identifier,
        ['@account'] = 'personal'
	})
    return result
end

GetSavingsStatement = function(source)
    local _src = source
    local xPlayer = ESX.GetPlayerFromId(_src)
    local result = MySQL.Sync.fetchAll('SELECT * FROM bank_statements WHERE `account` = @account AND `character_id` = @identifier', {
		['@identifier'] = xPlayer.identifier,
        ['@account'] = 'savings'
	})
    return result
end

AdjustStatement = function(source, action, account, amount, desc)
    local _src = source
    local _char = GetPlayerCharacter(_src)
    local _saving = GetPlayerSavings(_src)
    local xPlayer = ESX.GetPlayerFromId(_src)
    local time = os.date("%Y-%m-%d %H:%M:%S")
    if action == "deposit" then
        MySQL.Async.insert("INSERT INTO `bank_statements` (`account`,`character_id`,`account_number`,`sort_code`,`deposited`,`balance`,`date`,`message`) VALUES (@account, @cid, @accountnumber, @sortcode, @deposited, @balance, @date, @message)", {
            ['@account'] = account,
            ['@cid'] = xPlayer.identifier,
            ['@accountnumber'] = (account == "personal" and _char.account_number or _saving.account_number),
            ['@sortcode'] = (account == "personal" and _char.sort_code or _saving.sort_code),
            ['@deposited'] = amount,
            ['@balance'] = (account == "personal" and xPlayer.getAccount('bank').money or _saving.balance),
            ['@date'] = time,
            ['@message'] = desc
        }, function(done)
            if done > 0 then
                TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
            end
        end)
    else
        MySQL.Async.insert("INSERT INTO `bank_statements` (`account`,`character_id`,`account_number`,`sort_code`,`withdraw`,`balance`,`date`,`message`) VALUES (@account, @cid, @accountnumber, @sortcode, @deposited, @balance, @date, @message)", {
            ['@account'] = account,
            ['@cid'] = xPlayer.identifier,
            ['@accountnumber'] = (account == "personal" and _char.account_number or _saving.account_number),
            ['@sortcode'] = (account == "personal" and _char.sort_code or _saving.sort_code),
            ['@deposited'] = amount,
            ['@balance'] = (account == "personal" and xPlayer.getAccount('bank').money or _saving.balance),
            ['@date'] = time,
            ['@message'] = desc
        }, function(done)
            if done > 0 then
                TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
            end
        end)
    end
end

ESX.RegisterServerCallback('pw_banking:server:requestBankingInformation', function(source, cb)
    local _src = source
    local _char = GetPlayerCharacter(_src)
    local xPlayer = ESX.GetPlayerFromId(_src)
    local _char_saving = GetPlayerSavings(_src)
    local _char_data = {}
    _char_data.personal = {}
    _char_data.personal.meta = {}
    _char_data.savings = {}
    _char_data.savings.exist = CheckPlayerSavings(_src)
    _char_data.name = _char.firstname .. ' ' .. _char.lastname
    _char_data.personal.accountdetails = {}
    _char_data.personal.accountdetails.account_number = _char.account_number
    _char_data.personal.accountdetails.sort_code = _char.sort_code
    _char_data.personal.accountdetails.iban = _char.iban
    _char_data.personal.balance = xPlayer.getAccount('bank').money
    _char_data.personal.cash = xPlayer.getMoney()
    _char_data.savings.accountdetails = {}
    if _char_saving ~= nil then
        _char_data.savings.accountdetails.account_number = _char_saving.account_number
        _char_data.savings.accountdetails.sort_code = _char_saving.sort_code
        _char_data.savings.accountdetails.iban = _char_saving.iban
        _char_data.savings.balance = _char_saving.balance
    else
        _char_data.savings.accountdetails.account_number = nil
        _char_data.savings.accountdetails.sort_code = nil
        _char_data.savings.accountdetails.iban = nil
        _char_data.savings.balance = nil
    end
    _char_data.cardsexist = CheckPlayerCard(_src)
    _char_data.cards = GetPlayerCards(_src)
    _char_data.personal.statement = GetPlayerStatement(_src)
    _char_data.savings.statement = GetSavingsStatement(_src)
    cb(_char_data)
end)

getEverything = function(source)
    local _src = source
    local _char = GetPlayerCharacter(_src)
    local xPlayer = ESX.GetPlayerFromId(_src)
    local _char_saving = GetPlayerSavings(_src)
    local _char_data = {}
    _char_data.personal = {}
    _char_data.personal.meta = {}
    _char_data.savings = {}
    _char_data.savings.exist = CheckPlayerSavings(_src)
    _char_data.name = _char.firstname .. ' ' .. _char.lastname
    _char_data.personal.accountdetails = {}
    _char_data.personal.accountdetails.account_number = _char.account_number
    _char_data.personal.accountdetails.sort_code = _char.sort_code
    _char_data.personal.accountdetails.iban = _char.iban
    _char_data.personal.balance = xPlayer.getAccount('bank').money
    _char_data.personal.cash = xPlayer.getMoney()
    _char_data.savings.accountdetails = {}
    if _char_saving ~= nil then
        _char_data.savings.accountdetails.account_number = _char_saving.account_number
        _char_data.savings.accountdetails.sort_code = _char_saving.sort_code
        _char_data.savings.accountdetails.iban = _char_saving.iban
        _char_data.savings.balance = _char_saving.balance
    else
        _char_data.savings.accountdetails.account_number = nil
        _char_data.savings.accountdetails.sort_code = nil
        _char_data.savings.accountdetails.iban = nil
        _char_data.savings.balance = nil
    end
    _char_data.cardsexist = CheckPlayerCard(_src)
    _char_data.cards = GetPlayerCards(_src)
    _char_data.personal.statement = GetPlayerStatement(_src)
    _char_data.savings.statement = GetSavingsStatement(_src)
    return _char_data
end

CreateAccountSaving = function(source)
    local _src = source
    local _char = GetPlayerCharacter(_src)
    local xPlayer = ESX.GetPlayerFromId(_src)
    local accountNumber = math.random(10000000,99999999)
    local sortCode = _char.sort_code
    local IBAN = _char.iban.."-1"
    local createBankAccount = MySQL.Sync.insert("INSERT INTO `banking` (`cid`,`account_number`,`sort_code`,`balance`,`type`,`account_meta`,`iban`,`creditScore`) VALUES (@cid, @acct, @sc, @balance, @type, @meta, @iban, @cscore)", {
        ['@cid'] = xPlayer.identifier,
        ['@acct'] = accountNumber,
        ['@sc'] = sortCode,
        ['@balance'] = 0,
        ['@type'] = "Savings",
        ['@meta'] = json.encode({['overdraft'] = 0, ['currentloan'] = 0}),
        ['@iban'] = IBAN,
        ['@cscore'] = 0,
    })
end

RegisterServerEvent('pw_banking:server:CreatePersonalAccount')
AddEventHandler('pw_banking:server:CreatePersonalAccount', function()
    local _src = source
    local _char = GetPlayerCharacter(_src)
    local xPlayer = ESX.GetPlayerFromId(_src)
    if _char.account_number == nil or "" and _char.sort_code == nil or "" then
        MySQL.Async.execute("UPDATE users SET account_number = @account_number, sort_code = @sort_code, iban = @iban WHERE identifier = @identifier", {
            ['@account_number'] = math.random(10000000,99999999),
            ['@sort_code'] = math.random(10000000,99999999),
            ['@iban'] = math.random(10000000,99999999),
            ['@identifier'] = xPlayer.identifier
        }, function(rowsChanged) end)
    else
        return
    end
end)

RegisterServerEvent('pw_banking:server:requestOpenSavings')
AddEventHandler('pw_banking:server:requestOpenSavings', function()
    local _src = source
    local _char = ESX.GetPlayerFromId(_src)
    if _char then
        CreateAccountSaving(_src)
        TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
        Wait(150)
        TriggerClientEvent('pw_banking:client:savingsOpened', _src)
    end
end)

ToggleLock = function(card, cb) 
    MySQL.Async.fetchAll("SELECT * FROM `debitcards` WHERE `record_id` = @card", {['@card'] = card}, function(cardinfo)
        if cardinfo[1] ~= nil then
            local metaDecode = json.decode(cardinfo[1].cardmeta)
            if not metaDecode.stolen then
                metaDecode.locked = not metaDecode.locked
                MySQL.Async.execute("UPDATE `debitcards` SET `cardmeta` = @meta WHERE `record_id` = @card", {['@card'] = card, ['@meta'] = json.encode(metaDecode)}, function(done) end)
            end
        end
    end)
end

RegisterServerEvent('pw_banking:server:lockCard')
AddEventHandler('pw_banking:server:lockCard', function(data)
    if data then
        local _src = source
        ToggleLock(tonumber(data.card))
        TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
    end
end)

ToggleStolen = function(card, cb)
    MySQL.Async.fetchAll("SELECT * FROM `debitcards` WHERE `record_id` = @card", {['@card'] = card}, function(cardinfo)
        if cardinfo[1] ~= nil then
            local metaDecode = json.decode(cardinfo[1].cardmeta)
            if not metaDecode.stolen then
                local time = os.time(os.date("!*t"))
                local plus24 = (time + 86400)
                metaDecode.stolen = true
                metaDecode.locked = true
                metaDecode.stolenReport = time
                metaDecode.stolenDelete = plus24
                MySQL.Async.execute("UPDATE `debitcards` SET `cardmeta` = @meta WHERE `record_id` = @card", {['@card'] = card, ['@meta'] = json.encode(metaDecode)}, function(done) end)
            end
        end
    end)
end

RegisterServerEvent('pw_banking:server:stolenCard')
AddEventHandler('pw_banking:server:stolenCard', function(data)
    if data then
        local _src = source
        ToggleStolen(tonumber(data.card))
        TriggerClientEvent('pw_banking:client:sendUpdate', _src, getEverything(_src))
    end
end)

getFullName = function(src)
    local _char = GetPlayerCharacter(src)
    local name = _char.firstname .. ' ' .. _char.lastname
    return name
end

RegisterNetEvent('pw_banking:server:completeExternalTransfer')
AddEventHandler('pw_banking:server:completeExternalTransfer', function(data)
    if data then
        local _src = source
        local _char = ESX.GetPlayerFromId(_src)
        local _character = GetPlayerCharacter(_src)

        if _char then
            if _char.getAccount('bank').money >= tonumber(data.amount) then
                MySQL.Async.fetchAll("SELECT * FROM `banking` WHERE `account_number` = @ac AND `sort_code` = @sc", {['@ac'] = data.accountnumber, ['@sc'] = data.sortcode}, function(acct)
                    if acct[1] ~= nil and acct[1].cid ~= nil then
                        local _target = ESX.GetPlayerFromIdentifier(acct[1].cid)

                        if _target then
                            _char.removeAccountMoney('bank', tonumber(data.amount))
                            AdjustStatement(_char.source, "withdraw", "personal", data.amount, "Transfer to "..getFullName(_target.source))
                            if acct[1].type == "Personal" then
                                _target.addAccountMoney('bank', tonumber(data.amount))
                                AdjustStatement(_target.source, "deposit", "personal", data.amount, "Transfer from "..getFullName(_char.source))
                                TriggerClientEvent('pw_banking:client:externalTransferMessage', _src, "success", "Your transfer has been successfully made to "..getFullName(_target.source))
                            else
                                AddSavingMoney(_target.source, tonumber(data.amount), GetPlayerSavings(_target.source).cid)
                                AdjustStatement(_target.source, "deposit", "savings", data.amount, "Transfer from "..getFullName(_char.source))
                                TriggerClientEvent('pw_banking:client:externalTransferMessage', _src, "success", "Your transfer has been successfully made to "..getFullName(_target.source))
                            end
                        end
                    else
                        TriggerClientEvent('pw_banking:client:externalTransferMessage', _src, "danger", "The account number or sort code you have entered does not appear to exist.")
                    end
                end)
            end
        end
    end
end)

CreateCard = function(account, sortcode, pin, identifier)
    local cardType = math.random(1,2)
    local cardnumber
    if cardType == 1 then
        cardnumber = "4147"..math.random(100000000000,999999999999)
    else
        cardnumber = "5355"..math.random(100000000000,999999999999)
    end

    local generatedMeta = { ['cardPin'] = pin, ['account'] = account, ['sortcode'] = sortcode, ['locked'] = false, ['stolen'] = false }

    MySQL.Async.insert("INSERT INTO `debitcards` (`owner_cid`, `cardnumber`, `cardmeta`,`type`) VALUES (@cid, @number, @meta, @type)", {
        ['@cid'] = identifier,
        ['@number'] = cardnumber,
        ['@meta'] = json.encode(generatedMeta),
        ['@type'] = (cardType == 1 and "Visa" or "Mastercard")
    }, function(inserted) end) 
end

RegisterServerEvent('pw_banking:server:createDebitCard')
AddEventHandler('pw_banking:server:createDebitCard', function(data)
    if data then
        local _src = source
        local _char = ESX.GetPlayerFromId(_src)

        if _char then
            local _character = GetPlayerCharacter(_src)
            CreateCard(_character.account_number, _character.sort_code, tonumber(data.pin), _char.identifier)
        end
    end
end)

RegisterNetEvent('pw_banking:server:completeInternalTransfer')
AddEventHandler('pw_banking:server:completeInternalTransfer', function(data)
    if data then
        local _src = source
        local _char = ESX.GetPlayerFromId(_src)
        if _char then
            if data.from == "cash" then
                if _char.getMoney() >= tonumber(data.amount) then
                    _char.removeMoney(tonumber(data.amount))
                    if data.to == "current" then
                        _char.addAccountMoney('bank', tonumber(data.amount))
                        AdjustStatement(_src, "deposit", "personal", data.amount, "Cash Deposit")
                    else
                        local Saving_Owner = GetPlayerSavings(_src).cid
                        AddSavingMoney(_src, tonumber(data.amount), Saving_Owner)
                        AdjustStatement(_src, "deposit", "savings", data.amount, "Cash Deposit")
                    end
                end
            elseif data.from == "current" then
                _char.removeAccountMoney('bank', tonumber(data.amount))
                if data.to == "cash" then
                    _char.addMoney(tonumber(data.amount))
                else
                    local Saving_Owner = GetPlayerSavings(_src).cid
                    AddSavingMoney(_src, tonumber(data.amount), Saving_Owner)
                    AdjustStatement(_src, "deposit", "savings", data.amount, "Deposit from Current Account")
                end
            else
                if GetPlayerSavings(_src).balance >= tonumber(data.amount) then
                    RemoveSavingMoney(_src, tonumber(data.amount), GetPlayerSavings(_src).cid)
                    AdjustStatement(_src, "withdraw", "savings", data.amount, "Withdraw from Savings Account")
                    if to == "current" then
                        _char.addAccountMoney('bank', tonumber(data.amount))
                        AdjustStatement(_src, "deposit", "personal", data.amount, "Savings Transfer")
                    else
                        _char.addMoney(tonumber(data.amount))
                    end
                end
            end
        end
    end
end)