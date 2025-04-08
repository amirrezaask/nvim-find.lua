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

local function score(query, objects)
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
        local adjusted_score = overlap / math.sqrt(display_len + 1)
        objects[obj_idx].score = adjusted_score
    end
end

-- Example usage
-- local collection = {
--     { display = "cat",  score = 0 },
--     { display = "hat",  score = 0 },
--     { display = "bat",  score = 0 },
--     { display = "chat", score = 0 },
--     { display = "cake", score = 0 },
--     { display = "bake", score = 0 }
-- }
--
-- local query = "rat"
--
-- score(query, collection)
--
-- print("Query: " .. query)
-- for _, obj in ipairs(collection) do
--     print(string.format("Display: %-5s, Score: %.3f", obj.display, obj.score))
-- end
--
return score
