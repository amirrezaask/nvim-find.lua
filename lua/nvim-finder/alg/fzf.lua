---@param query string
---@param collection table<Finder.Entry>
return function(query, collection)
    local function get_matched_score(pattern, str)
        local function normalize_rune(r)
            if r >= 65 and r <= 90 then -- A-Z
                return r + 32           -- Convert to lowercase
            end
            return r
        end

        local function char_at(str, pos)
            return string.byte(str, pos)
        end


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
        local score = tonumber(0)
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
            return false, 0, nil
        end

        score = (tonumber(score) * 100 / tonumber(#str)) -- We want to have shorter items get higher score.
        return true, score, positions
    end

    if query == "" then return collection end
    for i, v in ipairs(collection) do
        local matched, score, _ = get_matched_score(query, v.display)
        collection[i].score = score
        collection[i].matched = matched
    end

    return collection
end
