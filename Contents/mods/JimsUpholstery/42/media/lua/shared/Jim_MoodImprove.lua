local function pickPlayer(a, b, c)
    if a and instanceof(a, "IsoPlayer") then return a end
    if b and instanceof(b, "IsoPlayer") then return b end
    if c and instanceof(c, "IsoPlayer") then return c end
    return nil
end

function Jim_MoodImprove(a, b, c)
    local player = pickPlayer(a, b, c)
    if not player then return end

    local stats = player:getStats()
    if not stats then return end

    -- clamp for safety
    local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

    stats:setBoredom(clamp(stats:getBoredom() - 30, 0, 100))
    stats:setStress(clamp(stats:getStress() - 0.2, 0.0, 1.0))
end
