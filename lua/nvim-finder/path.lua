local function shorten_path(path)
    local THRESHOLD = 40
    if not path or path == "" then
        return ""
    end

    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    local is_absolute = path:sub(1, 1) == "/"

    if #parts <= 1 then
        return path
    end

    -- Build the shortened path
    local result = {}
    for i, part in ipairs(parts) do
        if i >= #parts - 1 then
            table.insert(result, part)
        else
            table.insert(result, part:sub(1, 1))
        end
    end

    -- Join components and add leading slash if original was absolute
    local shortened = table.concat(result, "/")
    if is_absolute then
        shortened = "/" .. shortened
    end

    if #path < THRESHOLD then return path end

    return shortened
end

-- local test_paths = {
--     "/home/user/documents/project/file.txt",
--     "/usr/local/bin/script.sh",
--     "/var/www/html/index.html",
--     "relative/path/to/file.lua"
-- }
--
-- -- For testing individual shortening
-- for _, path in ipairs(test_paths) do
--     print(string.format("%s -> %s", path, shorten_path(path)))
-- end

return {
    shorten = shorten_path,
}
