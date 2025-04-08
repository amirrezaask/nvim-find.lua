local LOG_FILE = vim.fn.stdpath("data") .. '/nvim-finder.log'

return function(msg, ...)
    return;
    -- local args = { ... }
    -- local file = io.open(LOG_FILE, 'a')
    -- if file == nil then
    --     print("ERROR: cannot open nvim-finder log file: " .. LOG_FILE);
    --     return
    -- end
    -- file:write(string.format(msg, args) .. "\n")
    -- file:close()
end
