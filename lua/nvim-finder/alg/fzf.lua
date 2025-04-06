local function normalize_rune(r)
    if r >= 65 and r <= 90 then -- A-Z
        return r + 32           -- Convert to lowercase
    end
    return r
end

local function char_at(str, pos)
    return string.byte(str, pos)
end

local function fuzzy_match_v2(pattern, str)
    if #pattern == 0 then
        -- Empty pattern case
        -- 1. true: empty pattern matches any string
        -- 2. 0: no score since no actual matching occurred
        -- 3. nil: no positions to report
        return true, 0, nil
    end
    if #str == 0 then
        -- Empty string case with non-empty pattern
        -- 1. false: can't match pattern in empty string
        -- 2. 0: no score since matching failed
        -- 3. nil: no positions possible
        return false, 0, nil
    end

    -- Constants from original Go implementation
    local BONUS_FIRST_CHAR = 100
    local BONUS_BOUNDARY = 40
    local BONUS_NON_WORD = 20
    local BONUS_ADJACENT = 10
    local PENALTY_GAP = -5

    local pidx = 1
    local sidx = 1
    local plen = #pattern
    local slen = #str
    local pchar = normalize_rune(string.byte(pattern, 1))
    local matched = false
    local score = 0
    local positions = {}
    local inGap = false
    local firstMatch = -1

    while sidx <= slen do
        local schar = normalize_rune(char_at(str, sidx))

        if schar == pchar then
            matched = true
            positions[#positions + 1] = sidx

            -- Calculate bonus
            local bonus = 0
            if sidx == 1 then
                bonus = BONUS_FIRST_CHAR
            elseif sidx > 1 then
                local prevChar = char_at(str, sidx - 1)
                if prevChar == 32 or prevChar == 95 or prevChar == 45 then     -- space, underscore, hyphen
                    bonus = BONUS_BOUNDARY
                elseif prevChar < 48 or (prevChar > 57 and prevChar < 65) then -- non-word chars
                    bonus = BONUS_NON_WORD
                end
            end

            -- Adjacent bonus
            if pidx > 1 and sidx > 1 and positions[#positions - 1] == sidx - 1 then
                bonus = bonus + BONUS_ADJACENT
            end

            score = score + bonus
            if firstMatch == -1 then
                firstMatch = sidx
            end

            pidx = pidx + 1
            if pidx > plen then
                break
            end
            pchar = normalize_rune(string.byte(pattern, pidx))
            inGap = false
        else
            if matched and not inGap then
                score = score + PENALTY_GAP
                inGap = true
            end
        end
        sidx = sidx + 1
    end

    if pidx <= plen then
        -- Pattern not fully matched
        -- 1. false: indicates no complete match was found
        -- 2. 0: score is 0 since matching failed
        -- 3. nil: no positions to report since matching was incomplete
        return false, 0, nil
    end

    -- Successful match case
    -- 1. true: indicates the pattern was fully matched in the string
    -- 2. score: integer representing match quality (higher is better)
    --    - Adds bonuses for: first char (100), boundaries (40),
    --      non-word chars (20), adjacent matches (10)
    --    - Subtracts penalty (-5) for gaps between matches
    -- 3. positions: table containing 1-based indices where pattern chars matched
    return true, score, positions
end



---@param query string
---@param collection table<Finder.Entry>
return function(query, collection)
    if query == "" then return collection end
    for i, v in ipairs(collection) do
        local matched, score, _ = fuzzy_match_v2(query, v.display)
        if not matched then score = -math.huge end
        collection[i].score = score
    end

    return collection
end

-- -- Example usage
-- local function testMatch(pattern, str)
--     local matched, score, positions = fuzzy_match_v2(pattern, str)
--     print(string.format("Pattern: %s, String: %s", pattern, str))
--     print(string.format("Matched: %s, Score: %d", tostring(matched), score))
--     if positions then
--         print("Positions: " .. table.concat(positions, ", "))
--     end
--     print("")
-- end
--
-- -- Test cases
-- testMatch("abc", "abcde") -- Should match with high score due to consecutive matches
-- testMatch("abc", "a-b-c") -- Should match with boundary bonus
-- testMatch("fb", "foobar") -- Should match with first char bonus and gap penalty
-- testMatch("fb", "fbar")   -- Should match with first char bonus
