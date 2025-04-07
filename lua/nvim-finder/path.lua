-- Function to shorten a file path like Fish shell
local function shorten_path(path)
    -- If path is empty or nil, return empty string
    if not path or path == "" then
        return ""
    end

    -- Split path into components using forward slash
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    -- Handle absolute paths
    local is_absolute = path:sub(1, 1) == "/"

    -- If it's just a single component or empty, return as is
    if #parts <= 1 then
        return path
    end

    -- Build the shortened path
    local result = {}
    for i, part in ipairs(parts) do
        if i >= #parts - 1 then
            -- Last component keeps full name
            table.insert(result, part)
        else
            -- Take first character of intermediate directories
            table.insert(result, part:sub(1, 1))
        end
    end

    -- Join components and add leading slash if original was absolute
    local shortened = table.concat(result, "/")
    if is_absolute then
        shortened = "/" .. shortened
    end

    return shortened
end

-- -- Test the function
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
