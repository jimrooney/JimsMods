-- Version .2
-- JimsSewing_Context.lua
-- Portable Sewing Machine (B41/B42-safe)
-- Context menu + helpers that patch holes using the *direct* vanilla TA signature:
--   ISRepairClothing:new(player, clothing, bodyPartObj, fabricItem, threadItem, needleItem)
-- We ended up calling the vanilla action and trying every covered part,
-- because holes can be on arms, not just torso.

JimsSewing = JimsSewing or {}
JimsSewing.settings = JimsSewing.settings or { debug = false, radius = 2 }

local function dbg(...)
    if not JimsSewing.settings.debug then return end
    print("[JimsSewing]", ...)
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function normalizePlayer(arg)
    if type(arg) == "number" then return getSpecificPlayer(arg) end
    return arg
end

local function mainInv(player)
    if not player then return nil end
    return player:getInventory()
end

-- True iff the *inventory* contains a machine (this should fail the gate)
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

-- True if any world-inventory object on a square matches the machine
local function squareHasMachine(sq)
    if not sq then return false end
    local wios = sq:getWorldObjects()
    if not wios then return false end
    for i = 0, wios:size()-1 do
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

-- True iff a machine is placed within radius tiles around player (same Z)
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

-- GATE: must have a machine NEARBY, and must NOT have one in main inventory
local function machinePlacedNearbyNotInInventory(player)
    if playerHasMachineInventory(player) then
        dbg("Gate FAIL: machine is in inventory (must be placed).")
        return false
    end
    if not playerHasMachineNearbyWorld(player) then
        dbg("Gate FAIL: no placed machine within radius.")
        return false
    end
    dbg("Gate OK: placed machine nearby; none in inventory.")
    return true
end

--------------------------------------------------------------------------------
-- Core: queue vanilla repairs for ALL covered parts
--------------------------------------------------------------------------------
-- This is the version that actually worked in your client: it calls the vanilla
-- timed action, but tries every body part so we hit the one that really has the hole.
function JimsSewing.fixHolesInstant(target, clothing, player)
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
        print("[JimsSewing] no inventory")
        return
    end

    -- if no holes at all, bail right away
    if not clothing.getHolesNumber or clothing:getHolesNumber() <= 0 then
        print("[JimsSewing] item has no holes, skipping")
        return
    end

    local parts = clothing.getCoveredParts and clothing:getCoveredParts() or nil
    if not parts or parts:size() == 0 then
        print("[JimsSewing] clothing has no covered parts")
        return
    end

    local repairsQueued = 0
    local guard = 20

    for i = 0, parts:size() - 1 do
        -- check again inside the loop, so we stop after we’ve actually fixed it
        if clothing:getHolesNumber() <= 0 then
            break
        end
        if guard <= 0 then
            break
        end
        guard = guard - 1

        -- pick supplies fresh each time
        local fabric = inv:FindAndReturn("Base.LeatherStrips")
        if not fabric then fabric = inv:FindAndReturn("Base.DenimStrips") end
        if not fabric then fabric = inv:FindAndReturn("Base.RippedSheets") end

        local thread = inv:getFirstTagRecurse("Thread")
        if not thread then thread = inv:FindAndReturn("Base.Thread") end

        local needle = inv:getFirstTagRecurse("SewingNeedle")
        if not needle then needle = inv:FindAndReturn("Base.Needle") end
        if not needle then needle = inv:FindAndReturn("Base.SewingKit") end

        if not (fabric and thread and needle) then
            print("[JimsSewing] ran out of supplies while repairing")
            break
        end

        local partObj = parts:get(i)
        local act = ISRepairClothing:new(player, clothing, partObj, fabric, thread, needle)
        local ok, valid = pcall(function() return act:isValid() end)
        if ok and valid then
            ISTimedActionQueue.add(act)
            repairsQueued = repairsQueued + 1
        end
    end

    print(string.format("[JimsSewing] queued %d repair action(s) for %s", repairsQueued, tostring(clothing:getFullType())))
end







--------------------------------------------------------------------------------
-- Fully restore clothing
--------------------------------------------------------------------------------
-- fully restore clothing by replacing it with a fresh copy
function JimsSewing.restoreClothing(target, clothing, player)
    -- our menu will call with (nil, clothing, player)
    if not clothing then
        print("[JimsSewing] restoreClothing: no clothing")
        return
    end

    player = player or getSpecificPlayer(0)
    if not player then
        print("[JimsSewing] restoreClothing: no player")
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

    -- remember if it was worn
    local wasEquipped = clothing.isEquipped and clothing:isEquipped() or false

    -- remember color/tint if present
    local col = nil
    if clothing.getColor then
        col = clothing:getColor()
    end

    -- add a new clean item
    local fresh = inv:AddItem(ft)
    if not fresh then
        print("[JimsSewing] restoreClothing: failed to add fresh item")
        return
    end

    -- try to copy color back
    if col and fresh.setColor then
        fresh:setColor(col)
    end

    -- max condition, clean, dry
    if fresh.setCondition and fresh.getConditionMax then
        fresh:setCondition(fresh:getConditionMax())
    end
    if fresh.setBloodLevel then fresh:setBloodLevel(0) end
    if fresh.setDirtyness then fresh:setDirtyness(0) end
    if fresh.setWetness then fresh:setWetness(0) end

    -- equip it back if it was worn
    if wasEquipped and fresh.setWornItem then
        -- B42 way: player:setWornItem(fresh)
        pcall(function()
            player:setWornItem(fresh:getBodyLocation(), fresh)
        end)
    elseif wasEquipped and fresh:isClothing() then
        -- older pattern
        pcall(function()
            player:setClothingItem_Back(fresh)
        end)
    end

    -- finally remove the old damaged one
    inv:Remove(clothing)
    print("[JimsSewing] restoreClothing: replaced " .. tostring(ft) .. " with fresh copy")
end









------------------------------------------------------------
-- unwrap helper (unchanged)
------------------------------------------------------------
local function unwrapInventoryItem(entry)
    local item = entry
    while item and type(item) == "table" and item.items do
        item = item.items[1]
    end
    return item
end

------------------------------------------------------------
-- context menu
------------------------------------------------------------
local function OnFillInventoryObjectContextMenu(playerArg, context, items)
    -- HARD GUARDS
    if context == nil then return end
    if items == nil or #items == 0 then return end

    local player = normalizePlayer(playerArg)
    if player == nil then return end

    local picked = unwrapInventoryItem(items[1])
    if picked == nil then return end

    -- must be clothing with holes (for the sewing option)
    local holes = (picked.getHolesNumber and picked:getHolesNumber()) or 0

    -- must have placed machine nearby
    if not machinePlacedNearbyNotInInventory(player) then return end

    -- 1) your “instant repair” (vanilla TA over all parts)
    if holes > 0 then
        context:addOption(
            getText("Repair (Fix Holes)"),
            nil,
            JimsSewing.fixHolesInstant,
            picked,   -- clothing
            player    -- player
        )
    end

    -- 2) new “restore” option – we can allow this even without holes
    context:addOption(
        getText("Restore (Make New)"),
        nil,
        JimsSewing.restoreClothing,
        picked,
        player
    )
end

Events.OnFillInventoryObjectContextMenu.Add(OnFillInventoryObjectContextMenu)


-- reload confirmation
local ts = os.date and os.date("%X") or "now"
print("[JimsSewing] Context reloaded OK at " .. tostring(ts))
