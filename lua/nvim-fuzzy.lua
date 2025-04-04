vim.opt.runtimepath:append("~/src/nvim-fuzzy")
package.loaded["nvim-fuzzy"] = nil
package.loaded["nvim-fuzzy.find"] = nil
local uv = vim.loop

local function make_entry(e) return { actual = e, score = 0 } end
local function quicksort(arr)
	local l = 1
	local h = #arr
	local function partition(t, low, high)
		local i = (low - 1)
		local pivot = t[high]

		for j = low, high - 1 do
			if t[j].score >= pivot.score then
				i = i + 1
				t[i], t[j] = t[j], t[i]
			end
		end
		t[i + 1], t[high] = t[high], t[i + 1]
		return (i + 1)
	end

	local function table_with_size(size, default_value)
		local t = {}
		for _ = 1, size do
			table.insert(t, default_value)
		end
		return t
	end

	local size = h - l + 1
	local stack = table_with_size(size, 0)

	local top = -1
	top = top + 1
	stack[top] = l
	top = top + 1
	stack[top] = h

	while top >= 0 do
		h = stack[top]
		top = top - 1
		l = stack[top]
		top = top - 1
		local p = partition(arr, l, h)
		if p - 1 > l then
			top = top + 1
			stack[top] = l
			top = top + 1
			stack[top] = p - 1
		end
		if p + 1 < h then
			top = top + 1
			stack[top] = p + 1
			top = top + 1
			stack[top] = h
		end
	end
	return arr
end

local function string_distance(query, collection)
	local function ngrams_of(s, n)
		n = n or 3
		local ngrams = {}
		for i = 1, #s do
			local last = i + n - 1
			if last >= #s then last = #s end
			local this_ngram = string.sub(s, i, last)
			table.insert(ngrams, this_ngram)
		end
		return ngrams
	end

	local function levenshtein_distance(str1, str2)
		if str1 == str2 then return 0 end
		if #str1 == 0 then return #str2 end
		if #str2 == 0 then return #str1 end
		if str1 == str2 then return 0 end
		if str1:len() == 0 then return str2:len() end
		if str2:len() == 0 then return str1:len() end
		if str1:len() < str2:len() then
			str1, str2 = str2, str1
		end

		local t = {}
		for i = 1, #str1 + 1 do
			t[i] = { i - 1 }
		end

		for i = 1, #str2 + 1 do
			t[1][i] = i - 1
		end
		local function min(a, b, c)
			local min_val = a
			if b < min_val then min_val = b end
			if c < min_val then min_val = c end
			return min_val
		end
		local cost
		for i = 2, #str1 + 1 do
			for j = 2, #str2 + 1 do
				cost = (str1:sub(i - 1, i - 1) == str2:sub(j - 1, j - 1) and 0) or 1
				t[i][j] = min(t[i - 1][j] + 1, t[i][j - 1] + 1, t[i - 1][j - 1] + cost)
			end
		end
		return t[#str1 + 1][#str2 + 1]
	end
	if query == nil then return collection end
	for i = 1, #collection do
		if collection[i] ~= nil then
			local ngrams_data = ngrams_of(string.gsub(collection[i].actual, " ", ""), 3)
			local ngrams_query = ngrams_of(query:gsub(" ", ""), 3)
			local total = 0
			for _, nq in ipairs(ngrams_query) do
				local min_distance_of_ngrams = 100000
				for _, nd in ipairs(ngrams_data) do
					local distance = levenshtein_distance(string.lower(nq), string.lower(nd))
					if distance < min_distance_of_ngrams then min_distance_of_ngrams = distance end
				end
				total = total + min_distance_of_ngrams
			end
			collection[i].score = total
		end
	end
	return quicksort(collection)
end

local function call_find(path, callback)
	local handle
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)
	local results = {}

	handle = uv.spawn("find", {
		args = { path, "-type", "f", "-not", "-path", "**/.git/*" },
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		stdout:read_stop()
		stdout:close()
		handle:close()
		if code == 0 then callback(results) end
	end)

	uv.read_start(stderr, function(err, data)
		if err then
			print("stderr ", err)
			return
		end
		if data then print("stderr ", data) end
	end)

	uv.read_start(stdout, function(err, data)
		if err then
			vim.schedule(function() print(err) end)
			return
		end
		if data then
			local lines = vim.split(data, "\n")
			for _, line in ipairs(lines) do
				table.insert(results, line)
			end
		end
	end)
end

function new_fuzzy_finder(opts)
	assert(opts, "opts is required")
	assert(opts[1], "opts[1] source is required")
	assert(opts[2], "opts.[2] on_accept is required")
	opts.source = opts[1]
	opts.on_accept = opts[2]

	opts.user_input = opts.user_input or ""
	opts.make_entry = make_entry

	local row = math.floor(vim.o.lines * 0.3)
	local col = math.floor(vim.o.columns * 0.5)
	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * 0.7)
	local height = math.floor(vim.o.lines * 0.8)
	local win = vim.api.nvim_open_win(buf, true, {

		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
	})
	vim.cmd [[ startinsert ]]
	function opts.highlight(opts)
		vim.api.nvim_buf_clear_namespace(buf, opts.hl_ns, 0, -1)

		vim.api.nvim_win_set_cursor(win, { #opts.buf_lines, #opts.user_input + 1 })

		vim.hl.range(buf, opts.hl_ns, "Question", { opts.selected_item, 0 }, { opts.selected_item, width })
	end

	function opts.draw(opts)
		opts.buf_lines = {}
		local start = #opts.results - height - 2
		if start < 1 then start = 1 end
		for i = start, #opts.results do
			local v = opts.results[i]
			if v.actual and #v.actual > 0 then table.insert(opts.buf_lines, v.actual) end
		end

		table.insert(opts.buf_lines, opts.user_input) -- adds a line for prompt
		print(#opts.results, opts.source_elapsed, opts.sort_elapsed)
		if not opts.selected_item then opts.selected_item = #opts.results - 2 end

		if opts.selected_item < 0 then opts.selected_item = #opts.results - 2 end

		if opts.selected_item > #opts.results - 2 then opts.selected_item = 0 end
		if #opts.buf_lines == 0 then print("No results, return") end

		if not opts.buf_lines or #opts.buf_lines == 0 then return end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.buf_lines)

		opts:highlight()
	end

	function opts.set_keymaps(opts)
		vim.keymap.set({ "n", "i" }, "<C-n>", function()
			opts.selected_item = opts.selected_item + 1
			opts:highlight()
		end, { buffer = buf })

		vim.keymap.set({ "n", "i" }, "<C-p>", function()
			opts.selected_item = opts.selected_item - 1
			opts:highlight()
		end, { buffer = buf })

		vim.keymap.set({ "n", "i" }, "<CR>", function()
			local item = opts.results[opts.selected_item + 2]
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
			vim.cmd([[ quit! ]])
			vim.print(item)
			opts.on_accept(item)
		end, { buffer = buf })
	end

	function opts.setup_autocmds(opts)
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			buffer = buf,
			callback = function()
				local prev = opts.user_input
				opts.user_input = vim.api.nvim_get_current_line()
				if opts.results[#opts.results] then
					if opts.user_input == opts.results[#opts.results].actual then opts.user_input = "" end
				end
				if opts.user_input ~= prev then opts:source() end
			end,
		})
	end

	-- Initialize state
	opts.results = {}
	opts.buf_lines = {}
	opts.last_query = ""
	opts.hl_ns = vim.api.nvim_create_namespace("nvim-fuzzy")

	opts:set_keymaps()
	opts:setup_autocmds()
	opts:source()
end

new_fuzzy_finder {
	function(opts)
		if not opts.files_fetched then
			call_find(vim.fn.expand("~/.dotfiles"), function(res)
				opts.results = {}
				for _, v in ipairs(res) do
					table.insert(opts.results, { actual = v })
				end
				opts.files_fetched = true
				vim.schedule(function() opts:draw() end)
			end)
		else
			opts.results = string_distance(opts.user_input, opts.results)
			opts:draw()
		end
	end,
	function(e) vim.cmd.edit(e.actual) end,
}

return new_fuzzy_finder
