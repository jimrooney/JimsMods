-- media/lua/client/JimsSewing_MachinePatchTA.lua
require "TimedActions/ISBaseTimedAction"

JimsSewing_MachinePatchTA = ISBaseTimedAction:derive("JimsSewing_MachinePatchTA")

function JimsSewing_MachinePatchTA:isValid()
    -- keep whatever checks you already do for clothing + machine
    return self.clothing and self.clothing:isInPlayerInventory()
end

function JimsSewing_MachinePatchTA:start()
    -- optional: show sewing anim if you like
    self:setActionAnim("Sew")
    self.character:SetVariable("Sewing", true)

    -- start the looped sound we defined in sounditems.txt
    self.sound = self.character:getEmitter():playSound("sewing_machine")
end

function JimsSewing_MachinePatchTA:update()
    -- face the machine if you passed one in
    if self.machineObj then
        self.character:faceThisObject(self.machineObj)
    end
end

function JimsSewing_MachinePatchTA:stop()
    -- user cancelled / interrupted
    if self.sound then
        self.character:getEmitter():stopSound(self.sound)
        self.sound = nil
    end
    self.character:SetVariable("Sewing", false)
    ISBaseTimedAction.stop(self)
end

function JimsSewing_MachinePatchTA:perform()
    -- finished successfully
    if self.sound then
        self.character:getEmitter():stopSound(self.sound)
        self.sound = nil
    end
    self.character:SetVariable("Sewing", false)

    -- this is where you run your actual repair logic.
    -- call the same function you were calling from your context menu:
    if JimsSewing_DoRepair then
        -- if you made a helper, call it
        JimsSewing_DoRepair(self.character, self.clothing, self.bodyPartObj, self.fabricItem, self.threadItem)
    else
        -- or drop in the vanilla call you were using earlier:
        -- ISRepairClothing:new(player, clothing, bodyPartObj, fabricItem, threadItem, needleItem)
        -- you can require the right file at the top if needed
    end

    ISBaseTimedAction.perform(self)
end

function JimsSewing_MachinePatchTA:new(character, clothing, bodyPartObj, fabricItem, threadItem, machineObj)
    local o = ISBaseTimedAction.new(self, character)
    o.character    = character
    o.clothing     = clothing
    o.bodyPartObj  = bodyPartObj
    o.fabricItem   = fabricItem
    o.threadItem   = threadItem
    o.machineObj   = machineObj
    o.stopOnWalk   = true
    o.stopOnRun    = true
    o.maxTime      = 150 -- tweak: how long the sewing takes
    return o
end
