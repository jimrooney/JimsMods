--***********************************************************
-- JimsSewing_Context.lua
-- Final version – only repairs actual holes, using vanilla check:
--     clothing:getVisual():getHole(part) > 0
-- Requires: machine placed nearby (not in inventory)
--***********************************************************

JimsSewing = JimsSewing or {}
JimsSewing.settings = JimsSewing.settings or {
    debug  = false,   -- set to true if you want console spam
    radius = 2,
}

local function dbg(...)
    if not JimsSewing.settings.debug then return end
    print("[JimsSewing]", ...)
end

------------------------------------------------------------
-- basic helpers
------------------------------------------------------------
local function normalizePlayer(arg)
    if type(arg) == "number" then return getSpecificPlayer(arg) end
    return arg
end

local function mainInv(player)
    if not player then return nil end
    return player:getInventory()
end

-- machine present in inventory? (disallow – must be placed)
local function playerHasMachineInventory(player)
    player = normalizePlayer(player)
    if not player then return false end
    local inv = mainInv(player)
    if not inv then return false end

    if inv:FindAndReturn("Base.PortableSewingMachine")
    or inv:FindAndReturn("PortableSewingMachine")
    or inv:FindAndReturn("JimsUpholstery.PortableSewingMachine") then
        return true
    end

    -- fallback by display name
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getDisplayName and it:getDisplayName() == "Portable Sewing Machine" then
            return true
        end
    end
    return false
end

-- machine placed on this square?
local function squareHasMachine(sq)
    if not sq then return false end
    local wios = sq:getWorldObjects()
    if not wios then return false end
    for i = 0, wios:size() - 1 do
        local wio  = wios:get(i)
        local item = wio and wio:getItem()
        if item then
            local ft = item.getFullType and item:getFullType() or ""
            if ft == "Base.PortableSewingMachine"
            or ft == "PortableSewingMachine"
            or ft == "JimsUpholstery.PortableSewingMachine"
            or (item.getDisplayName and item:getDisplayName() == "Portable Sewing Machine") then
                return true
            end
        end
    end
    return false
end

-- machine placed nearby (same Z, within radius)?
local function playerHasMachineNearbyWorld(player, radius)
    player = normalizePlayer(player)
    radius = radius or JimsSewing.settings.radius or 2
    if not player then return false end

    local sq = player:getSquare()
    if not sq then return false end

    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local cell = getCell()

    for dx = -radius, radius do
        for dy = -radius, radius do
            local s = cell:getGridSquare(x + dx, y + dy, z)
            if squareHasMachine(s) then
                return true
            end
        end
    end

    return false
end

-- final gate
local function machinePlacedNearbyNotInInventory(player)
    if playerHasMachineInventory(player) then
        dbg("Gate FAIL: machine is in inventory (must be placed).")
        return false
    end
    if not playerHasMachineNearbyWorld(player) then
        dbg("Gate FAIL: no placed machine nearby.")
        return false
    end
    dbg("Gate OK: placed machine nearby; none in inventory.")
    return true
end


------------------------------------------------------------
-- Universal Mood Boost + XP Gain for Sewing Machine Use
------------------------------------------------------------
function JimsSewing.improveMood(player)
    if not player or player:isDead() then return end
    local stats = player:getStats()
    local body = player:getBodyDamage()

    local tailoring = player:getPerkLevel(Perks.Tailoring)

    -- scale 0.5×–2.0× depending on Tailoring level
    local factor = 0.5 + (tailoring / 10) * 1.5

    --------------------------------------------------------
    -- 🧘 Mood Improvements
    --------------------------------------------------------
    local boredomDelta     = 8  * factor
    local stressDelta      = 0.03 * factor
    local unhappinessDelta = 4  * factor
    local fatigueDelta     = 0.02 * factor

    -- Apply changes (clamped)
    if stats:getBoredom() > 0 then
        stats:setBoredom(math.max(0, stats:getBoredom() - boredomDelta))
    end
    if stats:getStress() > 0 then
        stats:setStress(math.max(0, stats:getStress() - stressDelta))
    end
    if body:getUnhappynessLevel() > 0 then
        body:setUnhappynessLevel(math.max(0, body:getUnhappynessLevel() - unhappinessDelta))
    end
    stats:setFatigue(math.min(1.0, stats:getFatigue() + fatigueDelta))

    --------------------------------------------------------
    -- 🎓 XP Reward (tunable)
    --------------------------------------------------------
    local baseXP = 2.0   -- <<--- change this number to set XP per use
    local xpGain = baseXP * factor
    player:getXp():AddXP(Perks.Tailoring, xpGain)

    --------------------------------------------------------
    -- 🧾 Debug output
    --------------------------------------------------------
    if JimsSewing.settings.debug then
        print(string.format(
            "[JimsSewing] Mood+XP (Tailoring=%d, factor=%.2f): boredom -%.1f, stress -%.2f, unhappy -%.1f, fatigue +%.2f, XP +%.2f",
            tailoring, factor, boredomDelta, stressDelta, unhappinessDelta, fatigueDelta, xpGain
        ))
    end
end



------------------------------------------------------------
-- (optional) hole dump – quieter when debug=false
------------------------------------------------------------
local function dumpHoles(clothing)
    if not JimsSewing.settings.debug then return end
    local vis = clothing.getVisual and clothing:getVisual() or nil
    print("[JimsSewing] Hole dump for", tostring(clothing:getFullType()))
    local parts = clothing.getCoveredParts and clothing:getCoveredParts() or nil
    if not parts or parts:size() == 0 then
        print("[JimsSewing]   no covered parts")
        return
    end
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        local holeCnt = nil
        if vis and vis.getHole then
            holeCnt = vis:getHole(part)
        end
        print(string.format("[JimsSewing]   part=%s hole=%s",
            tostring(part),
            tostring(holeCnt)))
    end
end

------------------------------------------------------------
-- core: fix ONLY parts where visual reports a hole
------------------------------------------------------------
function JimsSewing.fixHolesInstant(_, clothing, player)
    if not clothing then
        print("[JimsSewing] fixHolesInstant: no clothing")
        return
    end

    player = player or getSpecificPlayer(0)
    if not player then
        print("[JimsSewing] fixHolesInstant: no player")
        return
    end

    local inv = player:getInventory()
    if not inv then
        print("[JimsSewing] fixHolesInstant: player has no inventory")
        return
    end

    local totalHoles = clothing.getHolesNumber and clothing:getHolesNumber() or 0
    if totalHoles <= 0 then
        print("[JimsSewing] item has no holes, skipping")
        return
    end

    local parts = clothing.getCoveredParts and clothing:getCoveredParts() or nil
    if not parts or parts:size() == 0 then
        print("[JimsSewing] clothing has no covered parts")
        return
    end

    local vis = clothing:getVisual()
    if not (vis and vis.getHole) then
        print("[JimsSewing] clothing visual has no getHole(part); cannot target holes")
        return
    end

    dumpHoles(clothing)

    local repairsQueued = 0
    local guard = 30

    for i = 0, parts:size() - 1 do
        if guard <= 0 then break end
        guard = guard - 1

        -- short-circuit if item now has no holes
        if clothing:getHolesNumber() <= 0 then
            dbg("item reports 0 holes now; stopping")
            break
        end

        local partObj = parts:get(i)
        local holeCount = vis:getHole(partObj)

        -- vanilla logic: a hole exists if > 0
        if holeCount and holeCount > 0 then
            -- fabric priority: ripped sheets -> denim -> leather
            local fabric = inv:FindAndReturn("Base.RippedSheets")
            if not fabric then fabric = inv:FindAndReturn("Base.DenimStrips") end
            if not fabric then fabric = inv:FindAndReturn("Base.LeatherStrips") end

            local thread = inv:getFirstTagRecurse("Thread")
            if not thread then thread = inv:FindAndReturn("Base.Thread") end

            local needle = inv:getFirstTagRecurse("SewingNeedle")
            if not needle then needle = inv:FindAndReturn("Base.Needle") end
            if not needle then needle = inv:FindAndReturn("Base.SewingKit") end

            if not (fabric and thread and needle) then
                print("[JimsSewing] ran out of sewing supplies")
                break
            end

            local act = ISRepairClothing:new(player, clothing, partObj, fabric, thread, needle)
            local ok, valid = pcall(function() return act:isValid() end)
            if ok and valid then
                ISTimedActionQueue.add(act)
                repairsQueued = repairsQueued + 1
            else
                dbg("part not valid for repair:", tostring(partObj))
            end
        else
            dbg("skip clean part:", tostring(partObj))
        end
    end
    
    JimsSewing.improveMood(player)
    
    print(string.format("[JimsSewing] queued %d repair action(s) for %s",
        repairsQueued,
        tostring(clothing:getFullType())))
end

------------------------------------------------------------
-- restore clothing (requires Tailoring ≥ 8)
------------------------------------------------------------
function JimsSewing.restoreClothing(_, clothing, player)
    if not clothing then
        print("[JimsSewing] restoreClothing: no clothing")
        return
    end

    player = player or getSpecificPlayer(0)
    if not player then
        print("[JimsSewing] restoreClothing: no player")
        return
    end

    -- Tailoring level requirement
    local tailoring = player:getPerkLevel(Perks.Tailoring)
    if tailoring < 8 then
        player:Say(getText("IGUI_Tailoring_Level8Required") or "You need Tailoring level 8 to restore clothing.")
        print(string.format("[JimsSewing] restoreClothing: blocked (Tailoring %d < 8)", tailoring))
        return
    end

    local inv = player:getInventory()
    if not inv then
        print("[JimsSewing] restoreClothing: player has no inventory")
        return
    end

    local ft = clothing.getFullType and clothing:getFullType() or nil
    if not ft or ft == "" then
        print("[JimsSewing] restoreClothing: item has no full type")
        return
    end

    local wasEquipped = clothing.isEquipped and clothing:isEquipped() or false
    local col = clothing.getColor and clothing:getColor() or nil

    local fresh = inv:AddItem(ft)
    if not fresh then
        print("[JimsSewing] restoreClothing: failed to add fresh item")
        return
    end

    if col and fresh.setColor then
        fresh:setColor(col)
    end

    if fresh.setCondition and fresh.getConditionMax then
        fresh:setCondition(fresh:getConditionMax())
    end
    if fresh.setBloodLevel then fresh:setBloodLevel(0) end
    if fresh.setDirtyness then fresh:setDirtyness(0) end
    if fresh.setWetness then fresh:setWetness(0) end

    if wasEquipped and fresh.setWornItem then
        pcall(function()
            player:setWornItem(fresh:getBodyLocation(), fresh)
        end)
    elseif wasEquipped and fresh:isClothing() then
        pcall(function()
            player:setClothingItem_Back(fresh)
        end)
    end

    inv:Remove(clothing)
    JimsSewing.improveMood(player)
    print(string.format("[JimsSewing] restoreClothing: replaced %s with fresh copy (Tailoring %d)", tostring(ft), tailoring))
end


------------------------------------------------------------
-- unwrap helper
------------------------------------------------------------
local function unwrapInventoryItem(entry)
    local item = entry
    while item and type(item) == "table" and item.items do
        item = item.items[1]
    end
    return item
end

------------------------------------------------------------
-- context menu hook
------------------------------------------------------------
local function OnFillInventoryObjectContextMenu(playerArg, context, items)
    if not context or not items or #items == 0 then return end

    local player = normalizePlayer(playerArg)
    if not player then return end

    local picked = unwrapInventoryItem(items[1])
    if not picked then return end

    -- must have placed machine nearby
    if not machinePlacedNearbyNotInInventory(player) then return end

    local holes = (picked.getHolesNumber and picked:getHolesNumber()) or 0

    if holes > 0 then
        context:addOption(
            getText("Repair (Fix Holes)"),
            nil,
            JimsSewing.fixHolesInstant,
            picked,
            player
        )
    end

-- Add Restore option (always visible, but greyed out if Tailoring < 8)
local restoreText = getText("Restore (Make New)")
local restoreOption = context:addOption(restoreText, nil, JimsSewing.restoreClothing, picked, player)

local tailoring = player:getPerkLevel(Perks.Tailoring)
local tooltip = ISInventoryPaneContextMenu.addToolTip()
tooltip.description = ""

if tailoring < 8 then
    -- greyed-out visual + tooltip
    restoreOption.notAvailable = true
    tooltip.description = string.format(
        "%s <LINE>%s %d/8",
        getText("IGUI_Tailoring_Level8Required") or "Requires Tailoring level 8",
        getText("IGUI_perks_Tailoring") or "Tailoring:",
        tailoring
    )
else
    tooltip.description = string.format(
        "%s %d/10 <LINE>%s",
        getText("IGUI_perks_Tailoring") or "Tailoring:",
        tailoring,
        getText("IGUI_Tailoring_CanFullyRestore") or "You have the skill to fully restore clothing."
    )
end

restoreOption.toolTip = tooltip

end

Events.OnFillInventoryObjectContextMenu.Add(OnFillInventoryObjectContextMenu)

local ts = os.date and os.date("%X") or "now"
print("[JimsSewing] Context reloaded OK at " .. tostring(ts))
