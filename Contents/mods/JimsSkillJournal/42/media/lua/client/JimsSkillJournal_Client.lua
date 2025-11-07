--***********************************************************
-- JimsSkillJournal_Client.lua
--***********************************************************

JimsSkillJournal = JimsSkillJournal or {}

local function getPlayerIndex()
    local p = getSpecificPlayer(0)
    return p and p:getPlayerNum() or 0
end

local function addJournalOptions(player, context, items)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    local function unwrap(it)
        if it and it.items then
            return it.items[1]
        end
        return it
    end

    for _, v in ipairs(items) do
        local item = unwrap(v)
        if item and item:getFullType() == "JimsStuff.SkillJournal" then
            -- WRITE
            context:addOption("Write skills to journal", item, function(journal)
                sendClientCommand("JimsSkillJournal", "WriteSkills", {
                    itemID = journal:getID(),
                    playerIndex = getPlayerIndex(),
                })
            end)

            -- READ
            context:addOption("Read skills from journal", item, function(journal)
                sendClientCommand("JimsSkillJournal", "ReadSkills", {
                    itemID = journal:getID(),
                    playerIndex = getPlayerIndex(),
                })
            end)
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(addJournalOptions)
