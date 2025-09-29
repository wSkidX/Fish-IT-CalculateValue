
-- ===============================
-- INVENTORY + DISCORD WEBHOOK (Fixed Coins & Removed Quest)
-- ===============================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ===============================
-- SETUP & DATA ACCESS
-- ===============================
local Client = require(ReplicatedStorage.Packages.Replion).Client
local playerData = Client:WaitReplion("Data")

print("✅ Script loaded successfully!")
print("Webhook URL: " .. (getgenv().webhookUrl and "Set" or "Not set"))
print("Loop Interval: " .. getgenv().loopsendinterval .. " seconds")

-- ===============================
-- UTILITY
-- ===============================
local function getItemData(id)
    local Items = ReplicatedStorage.Items
    for _, item in pairs(Items:GetChildren()) do
        if item:IsA("ModuleScript") then
            local ok, data = pcall(require, item)
            if ok and data.Data and data.Data.Id == id then
                return data
            end
        end
    end
    return nil
end

local function getVariantData(variantName)
    local Variants = ReplicatedStorage:FindFirstChild("Variants")
    if not Variants then return nil end
    local variant = Variants:FindFirstChild(variantName)
    if variant and variant:IsA("ModuleScript") then
        local ok, data = pcall(require, variant)
        return ok and data or nil
    end
    return nil
end

local function getEnchantData(enchantId)
    local Enchants = ReplicatedStorage:FindFirstChild("Enchants")
    if not Enchants then return nil end
    for _, enchant in pairs(Enchants:GetChildren()) do
        if enchant:IsA("ModuleScript") then
            local ok, data = pcall(require, enchant)
            if ok and data.Data and data.Data.Id == enchantId then
                return data
            end
        end
    end
    return nil
end

local function formatNumber(num)
    if num >= 1000000000 then
        return string.format("%.2fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.2fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.2fK", num / 1000)
    end
    return tostring(math.floor(num))
end

-- ===============================
-- GET FRESH DATA FUNCTION
-- ===============================
local function getFreshData()
    -- Ambil data terbaru langsung dari Replion
    local freshInventoryData = playerData:Get("Inventory")
    local freshEquippedItems = playerData:Get("EquippedItems")
    local freshReplionData = playerData:Get()
    
    return freshInventoryData, freshEquippedItems, freshReplionData
end

-- ===============================
-- PLAYER INFO
-- ===============================
local function getPlayerData(replionData)
    local coins = replionData.Coins or 0
    local level = replionData.Level or 0
    local xp = replionData.XP or 0
    local xpRequired = replionData.XPRequired or 6568
    local masteryCount = 0

    if type(replionData.CaughtFishMastery) == "table" then
        for _ in pairs(replionData.CaughtFishMastery) do
            masteryCount += 1
        end
    end

    return {
        Name = LocalPlayer.DisplayName or LocalPlayer.Name,
        Level = level,
        XP = xp,
        XPRequired = xpRequired,
        Coins = coins,
        MasteryTypes = masteryCount,
        UserId = LocalPlayer.UserId
    }
end

-- ===============================
-- EQUIPPED ITEMS FROM EQUIPPEDITEMS DATA
-- ===============================
local function getEquippedItems(inventoryData, equippedItems)
    local equipped = {}
    
    if equippedItems then
        -- Cari rod yang equipped
        local rodSources = {inventoryData.Rods or {}, inventoryData.Items or {}, inventoryData["Fishing Rods"] or {}}
        
        for _, source in pairs(rodSources) do
            for _, item in pairs(source) do
                if type(item) == "table" and item.Id then
                    local data = getItemData(item.Id)
                    if data and data.Data and data.Data.Type == "Fishing Rods" then
                        local isEquipped = false
                        for _, equippedUUID in pairs(equippedItems) do
                            if equippedUUID == item.UUID then
                                isEquipped = true
                                break
                            end
                        end
                        if isEquipped then
                            -- Cek enchant pada rod
                            local enchantName = nil
                            if item.Metadata and item.Metadata.EnchantId then
                                local enchantData = getEnchantData(item.Metadata.EnchantId)
                                if enchantData then
                                    enchantName = enchantData.Data.Name
                                end
                            end
                            
                            equipped.Rod = {
                                Name = data.Data.Name,
                                Type = data.Data.Type,
                                Enchant = enchantName
                            }
                            break
                        end
                    end
                end
            end
            if equipped.Rod then break end
        end
        
        -- Cari bait yang equipped dari Items
        local itemSources = {inventoryData.Items or {}}
        for _, source in pairs(itemSources) do
            for _, item in pairs(source) do
                if type(item) == "table" and item.Id then
                    local data = getItemData(item.Id)
                    if data and data.Data and data.Data.Type == "Bait" then
                        local isEquipped = false
                        for _, equippedUUID in pairs(equippedItems) do
                            if equippedUUID == item.UUID then
                                isEquipped = true
                                break
                            end
                        end
                        if isEquipped then
                            equipped.Bait = {
                                Name = data.Data.Name,
                                Type = data.Data.Type
                            }
                            break
                        end
                    end
                end
            end
            if equipped.Bait then break end
        end
    end
    
    return equipped
end

-- ===============================
-- INVENTORY SUMMARY
-- ===============================
local function processInventorySummary(inventoryData)
    local fishSummary = {}
    local enchantStoneCount = 0
    local totalValue = 0
    local highestValueFish = {Name = "None", Price = 0}
    local sources = {inventoryData.Items or {}, inventoryData.Fish or {}, inventoryData.Fishes or {}}

    for _, source in pairs(sources) do
        for slot, item in pairs(source) do
            if type(item) == "table" and item.Id then
                local data = getItemData(item.Id)
                if data and data.Data then
                    local name = data.Data.Name
                    local typeName = data.Data.Type or "Unknown"

                    -- Hitung Enchant Stones (tidak dihitung harga)
                    if string.find(name, "Enchant Stone") then
                        enchantStoneCount += 1
                        continue
                    end

                    -- Skip Fishing Rods dan item non-fish
                    if typeName == "Fishing Rods" or typeName == "Bait" then
                        continue
                    end

                    -- Hitung harga fish saja
                    local basePrice = data.SellPrice or 0
                    local finalPrice = basePrice
                    local rarity = "Common"
                    local weight = 0
                    
                    -- Cek variant untuk multiplier dan rarity
                    if item.Metadata and item.Metadata.VariantId then
                        local variantData = getVariantData(item.Metadata.VariantId)
                        if variantData then
                            if variantData.SellMultiplier then
                                finalPrice = basePrice * variantData.SellMultiplier
                            end
                            if variantData.Rarity then
                                rarity = variantData.Rarity
                            end
                        end
                    end
                    
                    -- Cek weight dari metadata
                    if item.Metadata and item.Metadata.Weight then
                        weight = item.Metadata.Weight
                    end

                    totalValue = totalValue + finalPrice
                    
                    -- Update highest value fish
                    if finalPrice > highestValueFish.Price then
                        highestValueFish = {Name = name, Price = finalPrice}
                    end
                    
                    -- Group fish by name + rarity
                    local fishKey = name .. " (" .. rarity .. ")"
                    
                    if not fishSummary[fishKey] then
                        fishSummary[fishKey] = {
                            count = 0,
                            totalWeight = 0,
                            rarity = rarity
                        }
                    end
                    fishSummary[fishKey].count += 1
                    fishSummary[fishKey].totalWeight += weight
                end
            end
        end
    end

    return fishSummary, enchantStoneCount, totalValue, highestValueFish
end

-- ===============================
-- DISCORD WEBHOOK SENDER
-- ===============================
local function sendWebhook(embed)
    if not getgenv().webhookUrl or getgenv().webhookUrl == "YOUR_WEBHOOK_URL_HERE" then
        warn("❌ Webhook URL not set!")
        return false
    end

    local payload = {
        embeds = {embed}
    }

    local success, response = pcall(function()
        return request({
            Url = getgenv().webhookUrl,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = game:GetService("HttpService"):JSONEncode(payload)
        })
    end)

    if success then
        return true
    else
        warn("❌ Failed to send webhook: " .. tostring(response))
        return false
    end
end

-- ===============================
-- CREATE SUMMARY BOX
-- ===============================
local function createSummaryBox(fishSummary, enchantStoneCount)
    local lines = {}
    
    -- Add fish to summary
    for fishName, data in pairs(fishSummary) do
        local weightText = data.totalWeight > 0 and string.format(" (%.2f Kg)", data.totalWeight) or ""
        table.insert(lines, string.format("%s (x%d)%s", fishName, data.count, weightText))
    end
    
    -- Add enchant stones
    if enchantStoneCount > 0 then
        table.insert(lines, string.format("💎 Enchant Stone (x%d)", enchantStoneCount))
    end
    
    -- Jika tidak ada item
    if #lines == 0 then
        return "```No valuable fish found.```"
    end
    
    -- Buat box dengan format code block
    local boxContent = table.concat(lines, "\n")
    return "```" .. boxContent .. "```"
end

-- ===============================
-- MAIN OUTPUT FUNCTION
-- ===============================
local function processAndSend()
    local success, errorMsg = pcall(function()
        -- AMBIL DATA TERBARU SEBELUM PROSES
        local inventoryData, equippedItems, replionData = getFreshData()
        
        local playerInfo = getPlayerData(replionData)
        local equipped = getEquippedItems(inventoryData, equippedItems)
        local fishSummary, enchantStoneCount, totalValue, highestValueFish = processInventorySummary(inventoryData)

        -- Debug coins
        print("🪙 Raw Coins Data:", replionData.Coins)
        print("🪙 Formatted Coins:", formatNumber(playerInfo.Coins))

        -- Create Discord embed
        local embed = {
            title = "📊 Player Stats Update",
            color = 3447003,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            author = {
                name = playerInfo.Name,
                icon_url = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. playerInfo.UserId .. "&width=420&height=420&format=png"
            },
            fields = {}
        }

        -- Player Info
        table.insert(embed.fields, {
            name = "Player Info",
            value = string.format("Coins: **%s**\nLevel: **%d**\nXP: **%s / %s**", 
                formatNumber(playerInfo.Coins), 
                playerInfo.Level,
                formatNumber(playerInfo.XP),
                formatNumber(playerInfo.XPRequired)),
            inline = true
        })

        -- Equipped Items dengan Enchant
        local equippedText = ""
        if equipped.Rod then
            equippedText = equippedText .. "🎣 Rod: **" .. equipped.Rod.Name .. "**"
            if equipped.Rod.Enchant then
                equippedText = equippedText .. " ✨(" .. equipped.Rod.Enchant .. ")"
            end
            equippedText = equippedText .. "\n"
        else
            equippedText = equippedText .. "🎣 Rod: **None**\n"
        end
        
        if equipped.Bait then
            equippedText = equippedText .. "🪱 Bait: **" .. equipped.Bait.Name .. "**"
        else
            equippedText = equippedText .. "🪱 Bait: **None**"
        end

        table.insert(embed.fields, {
            name = "Equipped",
            value = equippedText,
            inline = true
        })


        -- Backpack Value
        local highestValueText = highestValueFish.Name ~= "None" and 
            string.format("💎 Highest Value Fish: **%s** (%s Coins)", highestValueFish.Name, formatNumber(highestValueFish.Price)) or
            "💎 Highest Value Fish: **None**"
        
        local valueText = totalValue > 0 and 
            string.format("Total Value: **%s Coins** 🪙\n%s", formatNumber(totalValue), highestValueText) or
            "Total Value: **0 Coins**\nNo valuable fish found."
        
        table.insert(embed.fields, {
            name = "Backpack Value",
            value = valueText,
            inline = false
        })

        -- Backpack Summary dalam Box
        local summaryBox = createSummaryBox(fishSummary, enchantStoneCount)
        
        table.insert(embed.fields, {
            name = "Backpack Summary",
            value = summaryBox,
            inline = false
        })

        -- Footer
        embed.footer = {
            text = "by : BDX7"
        }

        -- Send to Discord
        local sendSuccess = sendWebhook(embed)
        if sendSuccess then
            print("✅ Data sent to Discord - " .. os.date("%X"))
        end
        
    end)
    
    if not success then
        warn("❌ Error in processAndSend: " .. tostring(errorMsg))
    end
end

-- ===============================
-- AUTO LOOP FUNCTION
-- ===============================
local function startAutoLoop()
    print("🔄 Starting auto-send loop every " .. getgenv().loopsendinterval .. " seconds...")
    
    while true do
        local success, errorMsg = pcall(processAndSend)
        if not success then
            warn("❌ Error in auto loop: " .. tostring(errorMsg))
        end
        
        -- Tunggu interval
        for i = getgenv().loopsendinterval, 1, -1 do
            wait(1)
        end
    end
end

-- ===============================
-- EXECUTE
-- ===============================

-- Mulai loop otomatis
startAutoLoop()
