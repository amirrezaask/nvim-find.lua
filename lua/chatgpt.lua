vim.opt.runtimepath:append("~/src/nvim-fuzzy")
package.loaded["nvim-fuzzy"] = nil
package.loaded["nvim-fuzzy.find"] = nil
local uv = vim.loop

local function make_entry(e) return { actual = e, score = 0 } end
local function quicksort(arr)
	table.sort(arr, function(a, b) return a.score < b.score end)
	return arr
end

local function string_distance(query, collection)
	local function levenshtein_distance(str1, str2)
		if str1 == str2 then return 0 end
		if #str1 == 0 then return #str2 end
		if #str2 == 0 then return #str1 end

		local t = {}
		for i = 0, #str1 do
			t[i] = {}
		end
		for i = 0, #str1 do
			t[i][0] = i
		end
		for j = 0, #str2 do
			t[0][j] = j
		end

		for i = 1, #str1 do
			for j = 1, #str2 do
				local cost = (str1:sub(i, i) == str2:sub(j, j)) and 0 or 1
				t[i][j] = math.min(t[i - 1][j] + 1, t[i][j - 1] + 1, t[i - 1][j - 1] + cost)
			end
		end
		return t[#str1][#str2]
	end

	for i, item in ipairs(collection) do
		item.score = levenshtein_distance(query, item.actual)
	end
	return quicksort(collection)
end

local function call_find(path, callback)
	local results = {}
	local stdout = uv.new_pipe(false)

	local handle = uv.spawn("find", {
		args = { path, "-type", "f", "-not", "-path", "*/.git/*" },
		stdio = { nil, stdout, nil },
	}, function()
		uv.read_stop(stdout)
		stdout:close()
		vim.schedule(function() callback(results) end)
	end)

	uv.read_start(stdout, function(err, data)
		if err then return end
		if data then
			for line in data:gmatch("[^\r\n]+") do
				table.insert(results, { actual = line })
			end
		end
	end)
end

function new_fuzzy_finder(opts)
	assert(opts[1], "opts[1] source is required")
	assert(opts[2], "opts[2] on_accept is required")

	local state = {
		user_input = "",
		results = {},
		selected_item = 1,
		hl_ns = vim.api.nvim_create_namespace("nvim-fuzzy"),
	}

	local function redraw()
		local buf_lines = {}
		for _, item in ipairs(state.results) do
			table.insert(buf_lines, item.actual)
		end
		-- Preserve user input as the last line
		table.insert(buf_lines, state.user_input)
		vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, buf_lines)
		vim.api.nvim_win_set_cursor(state.win, { #buf_lines, 0 })
	end

	local function start_search()
		vim.schedule(function()
			if state.user_input and state.user_input ~= "" then state.results = string_distance(state.user_input, state.results) end
			redraw()
		end)
	end

	state.buf = vim.api.nvim_create_buf(false, true)
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = math.floor(vim.o.columns * 0.7),
		height = math.floor(vim.o.lines * 0.8),
		row = math.floor(vim.o.lines * 0.3),
		col = math.floor(vim.o.columns * 0.5),
		style = "minimal",
		border = "rounded",
	})

	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "" })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.buf,
		callback = function()
			local line_count = vim.api.nvim_buf_line_count(state.buf)
			local line = vim.api.nvim_buf_get_lines(state.buf, line_count - 1, line_count, false)[1]
			if line then
				state.user_input = line
				start_search()
			end
		end,
	})

	opts[1](state)
end

new_fuzzy_finder {
	function(state)
		call_find(vim.fn.expand("~/.dotfiles"), function(res)
			state.results = res
			vim.schedule(function() vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { state.user_input }) end)
		end)
	end,
	function(e) vim.cmd.edit(e.actual) end,
}

return new_fuzzy_finder
