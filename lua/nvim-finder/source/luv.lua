local uv = vim.loop


local function recursive_files(opts)
    opts = opts or {}

    opts.path = vim.fn.expand(opts.path)
    if opts.starting_directory == nil then opts.starting_directory = opts.path end
    opts.hidden = opts.hidden or false
    opts.exclude = opts.exclude or {}

    -- Normalize exclude to a list of glob patterns
    local exclude_patterns = {}
    if type(opts.exclude) == "string" then
        exclude_patterns = { opts.exclude }
    elseif vim.islist(opts.exclude) then
        exclude_patterns = opts.exclude
    end

    -- Checks if a path matches any exclude glob
    local function is_excluded(entry_path)
        for _, pattern in ipairs(exclude_patterns) do
            if entry_path:match(pattern) then
                return true
            end
        end
        return false
    end

    return function(update_notifier)
        uv.fs_opendir(opts.path, function(err, dir)
            if err then
                print("error reading directory", err)
                return
            end

            local function continue_reading_fs_entries()
                uv.fs_readdir(dir, function(err, entries)
                    if err then
                        uv.fs_closedir(dir)
                        print("error in reading directory", err)
                        return
                    end


                    local files = {}

                    if not entries then
                        uv.fs_closedir(dir)
                        return
                    end

                    for _, entry in ipairs(entries) do
                        local entry_path = opts.path .. "/" .. entry.name

                        -- Skip excluded entries based on glob
                        if is_excluded(entry_path) then
                            goto continue
                        end

                        -- Skip hidden files unless opts.hidden is true
                        if not opts.hidden and entry.name:sub(1, 1) == "." then
                            goto continue
                        end

                        if entry.type == 'file' then
                            table.insert(files, {
                                entry = entry_path,
                                -- display = entry_path:sub(#opts.starting_directory + 1),
                                display = entry_path,
                                score = 0
                            })
                        elseif entry.type == "directory" then
                            local new_opts = {}
                            for k, v in pairs(opts) do
                                new_opts[k] = v
                            end
                            new_opts.path = entry_path
                            vim.schedule(function()
                                recursive_files(new_opts)(update_notifier)
                            end)
                        end



                        update_notifier(files)

                        ::continue::
                    end

                    continue_reading_fs_entries()
                end)
            end

            continue_reading_fs_entries()
        end)
    end
end




-- recursive_files({
--     path = "~/src/nvim-finder/",
--     exclude = { ".git/**", "vendor/**" }
-- })(function(e)
--         vim.print(e)
--     end)
--



return recursive_files
