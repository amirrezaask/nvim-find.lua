local M = {}

---@param query string
---@param collection table<Finder.Entry>
function M.fzfV2(query, collection)
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

-- The lua implementation of the fzy string matching algorithm
-- CREDITS TO https://github.com/swarn/fzy-lua
---@param query string
---@param collection table<Finder.Entry>
function M.fzy(query, collection)
    local SCORE_GAP_LEADING = -0.005
    local SCORE_GAP_TRAILING = -0.005
    local SCORE_GAP_INNER = -0.01
    local SCORE_MATCH_CONSECUTIVE = 1.0
    local SCORE_MATCH_SLASH = 0.9
    local SCORE_MATCH_WORD = 0.8
    local SCORE_MATCH_CAPITAL = 0.7
    local SCORE_MATCH_DOT = 0.6
    local SCORE_MAX = math.huge
    local SCORE_MIN = -math.huge
    local MATCH_MAX_LENGTH = 1024
    local CASE_SENSITIVE = false


    local function has_match(needle, haystack, case_sensitive)
        if not case_sensitive then
            needle = string.lower(needle)
            haystack = string.lower(haystack)
        end

        local j = 1
        for i = 1, string.len(needle) do
            j = string.find(haystack, needle:sub(i, i), j, true)
            if not j then
                return false
            else
                j = j + 1
            end
        end

        return true
    end

    local function is_lower(c) return c:match("%l") end

    local function is_upper(c) return c:match("%u") end

    local function precompute_bonus(haystack)
        local match_bonus = {}

        local last_char = "/"
        for i = 1, string.len(haystack) do
            local this_char = haystack:sub(i, i)
            if last_char == "/" or last_char == "\\" then
                match_bonus[i] = SCORE_MATCH_SLASH
            elseif last_char == "-" or last_char == "_" or last_char == " " then
                match_bonus[i] = SCORE_MATCH_WORD
            elseif last_char == "." then
                match_bonus[i] = SCORE_MATCH_DOT
            elseif is_lower(last_char) and is_upper(this_char) then
                match_bonus[i] = SCORE_MATCH_CAPITAL
            else
                match_bonus[i] = 0
            end

            last_char = this_char
        end

        return match_bonus
    end

    local function compute(needle, haystack, D, M, case_sensitive)
        -- Note that the match bonuses must be computed before the arguments are
        -- converted to lowercase, since there are bonuses for camelCase.
        local match_bonus = precompute_bonus(haystack)
        local n = string.len(needle)
        local m = string.len(haystack)

        if not case_sensitive then
            needle = string.lower(needle)
            haystack = string.lower(haystack)
        end

        -- Because lua only grants access to chars through substring extraction,
        -- get all the characters from the haystack once now, to reuse below.
        local haystack_chars = {}
        for i = 1, m do
            haystack_chars[i] = haystack:sub(i, i)
        end

        for i = 1, n do
            D[i] = {}
            M[i] = {}

            local prev_score = SCORE_MIN
            local gap_score = i == n and SCORE_GAP_TRAILING or SCORE_GAP_INNER
            local needle_char = needle:sub(i, i)

            for j = 1, m do
                if needle_char == haystack_chars[j] then
                    local score = SCORE_MIN
                    if i == 1 then
                        score = ((j - 1) * SCORE_GAP_LEADING) + match_bonus[j]
                    elseif j > 1 then
                        local a = M[i - 1][j - 1] + match_bonus[j]
                        local b = D[i - 1][j - 1] + SCORE_MATCH_CONSECUTIVE
                        score = math.max(a, b)
                    end
                    D[i][j] = score
                    prev_score = math.max(score, prev_score + gap_score)
                    M[i][j] = prev_score
                else
                    D[i][j] = SCORE_MIN
                    prev_score = prev_score + gap_score
                    M[i][j] = prev_score
                end
            end
        end
    end

    -- Compute a matching score.
    --
    -- Args:
    --   needle (string): must be a subequence of `haystack`, or the result is
    --     undefined.
    --   haystack (string)
    --   case_sensitive (bool, optional): defaults to false
    --
    -- Returns:
    --   number: higher scores indicate better matches. See also `get_score_min`
    --     and `get_score_max`.
    local function score(needle, haystack, case_sensitive)
        local n = string.len(needle)
        local m = string.len(haystack)

        if n == 0 or m == 0 or m > MATCH_MAX_LENGTH or n > m then
            return SCORE_MIN
        elseif n == m then
            return SCORE_MAX
        else
            local D = {}
            local M = {}
            compute(needle, haystack, D, M, case_sensitive)
            return M[n][m]
        end
    end

    -- Compute the locations where fzy matches a string.
    --
    -- Determine where each character of the `needle` is matched to the `haystack`
    -- in the optimal match.
    --
    -- Args:
    --   needle (string): must be a subequence of `haystack`, or the result is
    --     undefined.
    --   haystack (string)
    --   case_sensitive (bool, optional): defaults to false
    --
    -- Returns:
    --   {int,...}: indices, where `indices[n]` is the location of the `n`th
    --     character of `needle` in `haystack`.
    --   number: the same matching score returned by `score`
    local function positions(needle, haystack, case_sensitive)
        local n = string.len(needle)
        local m = string.len(haystack)

        if n == 0 or m == 0 or m > MATCH_MAX_LENGTH or n > m then
            return {}, SCORE_MIN
        elseif n == m then
            local consecutive = {}
            for i = 1, n do
                consecutive[i] = i
            end
            return consecutive, SCORE_MAX
        end

        local D = {}
        local M = {}
        compute(needle, haystack, D, M, case_sensitive)

        local positions = {}
        local match_required = false
        local j = m
        for i = n, 1, -1 do
            while j >= 1 do
                if D[i][j] ~= SCORE_MIN and (match_required or D[i][j] == M[i][j]) then
                    match_required = (i ~= 1) and (j ~= 1) and (M[i][j] == D[i - 1][j - 1] + SCORE_MATCH_CONSECUTIVE)
                    positions[i] = j
                    j = j - 1
                    break
                else
                    j = j - 1
                end
            end
        end

        return positions, M[n][m]
    end

    -- Apply `has_match` and `positions` to an array of haystacks.
    --
    -- Args:
    --   needle (string)
    --   haystack ({string, ...})
    --   case_sensitive (bool, optional): defaults to false
    --
    -- Returns:
    --   {{idx, positions, score}, ...}: an array with one entry per matching line
    --     in `haystacks`, each entry giving the index of the line in `haystacks`
    --     as well as the equivalent to the return value of `positions` for that
    --     line.
    local function filter(needle, haystacks, case_sensitive)
        local result = {}

        for i, line in ipairs(haystacks) do
            if has_match(needle, line, case_sensitive) then
                local p, s = positions(needle, line, case_sensitive)
                table.insert(result, { i, p, s })
            end
        end

        return result
    end

    -- The lowest value returned by `score`.
    --
    -- In two special cases:
    --  - an empty `needle`, or
    --  - a `needle` or `haystack` larger than than `get_max_length`,
    -- the `score` function will return this exact value, which can be used as a
    -- sentinel. This is the lowest possible score.
    function get_score_min() return SCORE_MIN end

    -- The score returned for exact matches. This is the highest possible score.
    function get_score_max() return SCORE_MAX end

    -- The maximum size for which `fzy` will evaluate scores.
    function get_max_length() return MATCH_MAX_LENGTH end

    -- The minimum score returned for normal matches.
    --
    -- For matches that don't return `get_score_min`, their score will be greater
    -- than than this value.
    function get_score_floor() return MATCH_MAX_LENGTH * SCORE_GAP_INNER end

    -- The maximum score for non-exact matches.
    --
    -- For matches that don't return `get_score_max`, their score will be less than
    -- this value.
    function get_score_ceiling() return MATCH_MAX_LENGTH * SCORE_MATCH_CONSECUTIVE end

    -- The name of the currently-running implmenetation, "lua" or "native".
    function get_implementation_name() return "lua" end

    if query == "" then return collection end
    for i, entry in ipairs(collection) do
        if has_match(query, entry.display, CASE_SENSITIVE) then
            local _, s = positions(query, entry.display, CASE_SENSITIVE)
            collection[i].score = s
            collection[i].matched = true
        else
            collection[i].matched = false
        end
    end

    return collection
end

function M.ngram_indexing(query, objects)
    -- Helper function to generate n-grams from a string
    local function generate_ngrams(str, n)
        local ngrams = {}
        str = str:lower() -- Case-insensitive matching
        local len = #str
        if len < n then
            return { str } -- If string is shorter than n, return it as a single n-gram
        end
        for i = 1, len - n + 1 do
            table.insert(ngrams, str:sub(i, i + n - 1))
        end
        return ngrams
    end

    -- Build the inverted index from a list of objects
    local function build_inverted_index(objects, n)
        local index = {}
        for idx, obj in ipairs(objects) do
            local ngrams = generate_ngrams(obj.display, n)
            for _, ngram in ipairs(ngrams) do
                if not index[ngram] then
                    index[ngram] = {}
                end
                table.insert(index[ngram], idx)
            end
        end
        return index
    end


    local n = 2
    local index = build_inverted_index(objects, n)
    for _, obj in ipairs(objects) do
        obj.score = 0
    end

    local query_ngrams = generate_ngrams(query, n)

    local raw_scores = {}
    for _, ngram in ipairs(query_ngrams) do
        if index[ngram] then
            for _, obj_idx in ipairs(index[ngram]) do
                raw_scores[obj_idx] = (raw_scores[obj_idx] or 0) + 1
            end
        end
    end

    -- Apply length-adjusted scoring
    for obj_idx, overlap in pairs(raw_scores) do
        local display_len = #objects[obj_idx].display
        -- Boost shorter strings: divide by a function of length (e.g., sqrt or log)
        -- Adding 1 to avoid division by zero or overly harsh penalties for short strings
        local adjusted_score = (overlap / math.sqrt(display_len + 1)) * 100
        objects[obj_idx].score = adjusted_score
    end
end

return M
