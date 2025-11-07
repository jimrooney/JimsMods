--***********************************************************
-- JimsSkillJournal_Server.lua
-- Save skills to item AND world ModData so they persist across deaths
--***********************************************************

local PERK_LIST = {
    "Aiming", "Reloading", "Woodwork", "Cooking", "Farming",
    "FirstAid", "Electrical", "MetalWelding", "Mechanics",
    "Tailoring", "Fishing", "Trapping", "Foraging",
    "Strength", "Fitness",
}

local WORLD_KEY = "JimsSkillJournal"   -- world-level ModData key

-- get or create the world store
local function getWorldStore()
    return ModData.getOrCreate(WORLD_KEY)
end

-- safely resolve player
local function resolvePlayer(playerObj, args)
    if playerObj then return playerObj end
    if args and args.playerIndex ~= nil then
        local p = getSpecificPlayer(args.playerIndex)
        if p then return p end
    end
    return getSpecificPlayer(0)
end

-- find an item by ID
local function getItemByID(playerObj, itemID)
    if not playerObj or not itemID then return nil end
    local inv = playerObj:getInventory()
    if not inv then return nil end
    return inv:getItemById(itemID)
end

----------------------------------------------------------------
-- WRITE SKILLS
----------------------------------------------------------------
local function writeSkillsToJournal(playerObj, journal)
    if not playerObj or not journal then return end

    local xp = playerObj:getXp()
    if not xp then
        print("[JSJ] player has no XP object on write")
        return
    end

    local mdItem = journal:getModData()
    mdItem.JSJ = mdItem.JSJ or {}
    mdItem.JSJ.skills = mdItem.JSJ.skills or {}
    mdItem.JSJ.fallbackApplied = {}

    local worldStore = getWorldStore()
    local jid = tostring(journal:getID())
    worldStore[jid] = worldStore[jid] or {}
    worldStore[jid].skills = worldStore[jid].skills or {}
    worldStore[jid].fallbackApplied = {}

    for _, perkName in ipairs(PERK_LIST) do
        local perkEnum = Perks[perkName]
        if perkEnum and xp.getXP then
            local current = xp:getXP(perkEnum)
            local prev = mdItem.JSJ.skills[perkName] or 0
            if current > prev then
                mdItem.JSJ.skills[perkName] = current
                mdItem.JSJ.fallbackApplied[perkName] = false
                worldStore[jid].skills[perkName] = current
                worldStore[jid].fallbackApplied[perkName] = false
                print(string.format("[JSJ] wrote %s = %.2f", perkName, current))
            end
        end
    end

    if journal.transmitModData then journal:transmitModData() end
    ModData.transmit(WORLD_KEY)

    local name = playerObj.getDisplayName and (playerObj:getDisplayName() or "Player") or "Player"
    print("[JSJ] " .. name .. " wrote skills to journal (" .. jid .. ")")
end

----------------------------------------------------------------
-- GET SAVED DATA (item or world)
----------------------------------------------------------------
local function getJSJForJournal(journal)
    if not journal then return nil, nil, nil end
    local jid = tostring(journal:getID())

    local mdItem = journal:getModData()
    if mdItem and mdItem.JSJ then
        return mdItem.JSJ, jid, "item"
    end

    local worldStore = getWorldStore()
    local entry = worldStore[jid]
    if entry then
        return entry, jid, "world"
    end

    return nil, jid, nil
end

----------------------------------------------------------------
-- READ SKILLS
----------------------------------------------------------------
local function readSkillsFromJournal(playerObj, journal)
    if not playerObj or not journal then return end

    local jsjRoot, jid, source = getJSJForJournal(journal)
    if not jsjRoot then
        print("[JSJ] journal has no saved skills")
        return
    end

    if type(jsjRoot.skills) ~= "table" then
        print("[JSJ] saved data has no skills table (source=" .. tostring(source) .. ")")
        return
    end
    if type(jsjRoot.fallbackApplied) ~= "table" then
        jsjRoot.fallbackApplied = {}
    end

    local xp = playerObj:getXp()
    if not xp then
        print("[JSJ] player has no XP object on read")
        return
    end

    local appliedAny = false
    local changedJSJ = false

    for perkName, savedXP in pairs(jsjRoot.skills) do
        local perkEnum = Perks[perkName]
        if perkEnum then
            if xp.getXP and xp.setXP then
                local currentXP = xp:getXP(perkEnum)
                if savedXP > currentXP then
                    xp:setXP(perkEnum, savedXP)
                    appliedAny = true
                    print(string.format("[JSJ] applied %s -> %.2f (setXP, from %s)", perkName, savedXP, source))
                end
            else
                -- MP-safe fallback path
                if not jsjRoot.fallbackApplied[perkName] then
                    if xp.AddXP then
                        xp:AddXP(perkEnum, savedXP, false, true, true) -- <-- MP-safe flags
                        jsjRoot.fallbackApplied[perkName] = true
                        appliedAny = true
                        changedJSJ = true
                        print(string.format("[JSJ] applied %s + %.2f (AddXP fallback, from %s)", perkName, savedXP, source))
                    else
                        print("[JSJ] no AddXP for " .. perkName)
                    end
                else
                    print("[JSJ] fallback already applied, skipping " .. perkName)
                end
            end
        end
    end

    if changedJSJ then ModData.transmit(WORLD_KEY) end
    if journal.transmitModData then journal:transmitModData() end
    if appliedAny and playerObj.syncXp then playerObj:syncXp() end

    local name = playerObj.getDisplayName and (playerObj:getDisplayName() or "Player") or "Player"
    print("[JSJ] " .. name .. " restored skills from journal (" .. tostring(jid) .. ") from " .. (source or "unknown"))
end

----------------------------------------------------------------
-- COMMAND DISPATCH
----------------------------------------------------------------
local function onClientCommand(module, command, playerObj, args)
    if module ~= "JimsSkillJournal" then return end
    playerObj = resolvePlayer(playerObj, args)
    if not playerObj then
        print("[JSJ] could not resolve player for command:", command)
        return
    end

    local journal = getItemByID(playerObj, args.itemID)
    if not journal then
        print("[JSJ] item not found on player")
        return
    end

    if command == "WriteSkills" then
        writeSkillsToJournal(playerObj, journal)
    elseif command == "ReadSkills" then
        readSkillsFromJournal(playerObj, journal)
    end
end

Events.OnClientCommand.Add(onClientCommand)
