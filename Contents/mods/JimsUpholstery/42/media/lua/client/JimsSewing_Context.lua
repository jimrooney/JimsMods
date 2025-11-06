--***********************************************************
-- JimsSewing_Context.lua
-- Final version – repairs only actual holes via vanilla logic.
-- Requires: machine placed nearby (not in inventory).
-- Plays sewing_machine.ogg via PlayWorldSound when used.
--***********************************************************

JimsSewing = JimsSewing or {}
JimsSewing.settings = JimsSewing.settings or {
    debug  = false,   -- set true for console output
    radius = 2,
}

local function dbg(...)
    if JimsSewing.settings.debug then
        print("[JimsSewing]", ...)
    end
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function normalizePlayer(arg)
    if type(arg) == "number" then return getSpecificPlayer(arg) end
    return arg
end

local function mainInv(player)
    if not player then return nil end
    return player:getInventory()
end

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

local function machinePlacedNearbyNotInInventory(player)
    if playerHasMachineInventory(player) then
        dbg("FAIL: machine in inventory (must be placed).")
        return false
    end
    if not playerHasMachineNearbyWorld(player) then
        dbg("FAIL: no placed machine nearby.")
        return false
    end
    dbg("OK: placed machine nearby.")
    return true
end

------------------------------------------------------------
-- Mood + XP Boost
------------------------------------------------------------
function JimsSewing.improveMood(player)
    if not player or player:isDead() then return end
    local stats = player:getStats()
    local body  = player:getBodyDamage()
    local tailoring = player:getPerkLevel(Perks.Tailoring)
    local factor = 0.5 + (tailoring / 10) * 1.5

    local boredomDelta     = 8  * factor
    local stressDelta      = 0.03 * factor
    local unhappinessDelta = 4  * factor
    local fatigueDelta     = 0.02 * factor

    stats:setBoredom(math.max(0, stats:getBoredom() - boredomDelta))
    stats:setStress(math.max(0, stats:getStress() - stressDelta))
    body:setUnhappynessLevel(math.max(0, body:getUnhappynessLevel() - unhappinessDelta))
    stats:setFatigue(math.min(1.0, stats:getFatigue() + fatigueDelta))

    local baseXP = 2.0
    local xpGain = baseXP * factor
    player:getXp():AddXP(Perks.Tailoring, xpGain)

    if JimsSewing.settings.debug then
        print(string.format("[JimsSewing] Mood+XP Tailoring=%d XP+%.2f", tailoring, xpGain))
    end
end

------------------------------------------------------------
-- Fix holes
------------------------------------------------------------
function JimsSewing.fixHolesInstant(_, clothing, player)
    if not clothing or not player then return end
    local inv = player:getInventory()
    if not inv then return end

    local totalHoles = clothing.getHolesNumber and clothing:getHolesNumber() or 0
    if totalHoles <= 0 then
        print("[JimsSewing] no holes, skipping")
        return
    end

    local parts = clothing:getCoveredParts()
    if not parts or parts:size() == 0 then return end
    local vis = clothing:getVisual()
    if not vis or not vis.getHole then return end

    -- 🔊 play the sewing sound
    local sq = player:getSquare()
    if sq then
        getSoundManager():PlayWorldSound("sewing_machine", sq, 0, 1, 10, false)
    end

    local repairsQueued = 0
    for i = 0, parts:size() - 1 do
        if clothing:getHolesNumber() <= 0 then break end
        local partObj = parts:get(i)
        local holeCount = vis:getHole(partObj)
        if holeCount and holeCount > 0 then
            local fabric = inv:FindAndReturn("Base.RippedSheets")
                or inv:FindAndReturn("Base.DenimStrips")
                or inv:FindAndReturn("Base.LeatherStrips")
            local thread = inv:getFirstTagRecurse("Thread") or inv:FindAndReturn("Base.Thread")
            local needle = inv:getFirstTagRecurse("SewingNeedle")
                or inv:FindAndReturn("Base.Needle")
                or inv:FindAndReturn("Base.SewingKit")

            if not (fabric and thread and needle) then break end
            local act = ISRepairClothing:new(player, clothing, partObj, fabric, thread, needle)
            if act:isValid() then
                ISTimedActionQueue.add(act)
                repairsQueued = repairsQueued + 1
            end
        end
    end

    JimsSewing.improveMood(player)
    print(string.format("[JimsSewing] queued %d repair action(s) for %s", repairsQueued, tostring(clothing:getFullType())))
end

------------------------------------------------------------
-- Restore clothing (Tailoring ≥ 8)
------------------------------------------------------------
function JimsSewing.restoreClothing(_, clothing, player)
    if not clothing or not player then return end
    local tailoring = player:getPerkLevel(Perks.Tailoring)
    if tailoring < 8 then
        player:Say("You need Tailoring level 8 to restore clothing.")
        return
    end

    local inv = player:getInventory()
    local ft = clothing:getFullType()
    if not ft or ft == "" then return end
    local wasEquipped = clothing:isEquipped()
    local col = clothing:getColor()

    local fresh = inv:AddItem(ft)
    if fresh then
        if col then fresh:setColor(col) end
        if fresh.setCondition and fresh.getConditionMax then
            fresh:setCondition(fresh:getConditionMax())
        end
        fresh:setBloodLevel(0)
        fresh:setDirtyness(0)
        fresh:setWetness(0)
    end

    if wasEquipped then
        pcall(function()
            player:setWornItem(fresh:getBodyLocation(), fresh)
        end)
    end

    inv:Remove(clothing)
    JimsSewing.improveMood(player)
    print(string.format("[JimsSewing] restored %s (Tailoring %d)", tostring(ft), tailoring))
end

------------------------------------------------------------
-- Context menu
------------------------------------------------------------
local function unwrapInventoryItem(entry)
    local item = entry
    while item and type(item) == "table" and item.items do
        item = item.items[1]
    end
    return item
end

local function OnFillInventoryObjectContextMenu(playerArg, context, items)
    if not context or not items or #items == 0 then return end
    local player = normalizePlayer(playerArg)
    local picked = unwrapInventoryItem(items[1])
    if not player or not picked then return end

    if not machinePlacedNearbyNotInInventory(player) then return end
    local holes = (picked.getHolesNumber and picked:getHolesNumber()) or 0

    if holes > 0 then
        context:addOption(getText("Repair (Fix Holes)"), nil, JimsSewing.fixHolesInstant, picked, player)
    end

    local restoreText = getText("Restore (Make New)")
    local restoreOption = context:addOption(restoreText, nil, JimsSewing.restoreClothing, picked, player)

    local tailoring = player:getPerkLevel(Perks.Tailoring)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    tooltip.description = ""

    if tailoring < 8 then
        restoreOption.notAvailable = true
        tooltip.description = string.format("%s <LINE>%s %d/8", "Requires Tailoring level 8", "Tailoring:", tailoring)
    else
        tooltip.description = string.format("%s %d/10 <LINE>%s", "Tailoring:", tailoring, "You can fully restore clothing.")
    end

    restoreOption.toolTip = tooltip
end

Events.OnFillInventoryObjectContextMenu.Add(OnFillInventoryObjectContextMenu)

print("[JimsSewing] Context reloaded OK at " .. tostring(os.date("%X") or "now"))
