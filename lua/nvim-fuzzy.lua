vim.opt.runtimepath:append("~/src/nvim-fuzzy")
package.loaded["nvim-fuzzy"] = nil
package.loaded["nvim-fuzzy.fzy"] = nil
local uv = vim.uv

local MEASURE = function(f)
	local start = vim.uv.hrtime()
	f()

	return (vim.uv.hrtime() - start) / 1e6
end
local function call_find(path, callback)
	local handle
	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)
	local results = {}

	handle = uv.spawn("find", {
		args = { path, "-type", "f", "-not", "-path", "**/.git/*", "-not", "-path", "**/vendor/**" },
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

---@class FuzzyFinder.Input
---@field [1] table<string>
---@field [2] func(selected: string)
---@function new_fuzzy_finder
---@param input FuzzyFinder.Input
function new_fuzzy_finder(input)
	assert(input, "input is required")
	assert(input[1], "opts[1] source is required, should be a table")
	assert(type(input[1]) == "table")
	assert(input[2], "opts.[2] on_accept is required")

	local opts = {
		[1] = input[1],
		[2] = input[2],
		user_input = "",
	}

	opts.source = opts[1]
	opts.on_accept = opts[2]
	opts.selected_item = #opts.source - 2

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

	opts.hl_ns = vim.api.nvim_create_namespace("nvim-fuzzy")
	function opts.highlight(opts)
		vim.api.nvim_buf_clear_namespace(buf, opts.hl_ns, 0, -1)

		vim.api.nvim_win_set_cursor(win, { #opts.buf_lines, #opts.user_input + 1 })

		vim.hl.range(buf, opts.hl_ns, "Visual", { opts.selected_item, 0 }, { opts.selected_item, width })
	end

	function opts.draw(opts)
		local prev = opts.user_input
		opts.user_input = vim.api.nvim_get_current_line()
		if opts.user_input ~= prev then
			local start = vim.uv.hrtime()
			local scores = require("nvim-fuzzy.fzy")(opts.user_input, opts.source)
			if scores ~= nil then
				table.sort(scores, function(a, b) return a[2] < b[2] end) -- ascending
				opts.buf_lines = {}
				for _, v in ipairs(scores) do
					table.insert(opts.buf_lines, string.format("%02X %s", v[2] or 0, opts.source[v[1]]))
				end

				table.insert(opts.buf_lines, opts.user_input) -- adds a line for prompt
			end
			local sort_elapsed = (vim.uv.hrtime() - start) / 1e6

			print(#opts.source, "sort/ms", sort_elapsed)
		end

		if opts.buf_lines == nil then opts.buf_lines = {} end

		if not opts.selected_item then opts.selected_item = #opts.source - 2 end

		if #opts.source > height and opts.selected_item < #opts.source - height then opts.selected_item = #opts.source - 2 end

		if opts.selected_item < 0 then opts.selected_item = #opts.source - 2 end

		if opts.selected_item > #opts.source - 2 then opts.selected_item = 0 end

		if #opts.buf_lines == 0 then print("No results, return") end

		if not opts.buf_lines or #opts.buf_lines == 0 then return end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.buf_lines)

		opts:highlight()
	end

	vim.keymap.set({ "n", "i" }, "<C-n>", function()
		opts.selected_item = opts.selected_item + 1
		opts:highlight()
	end, { buffer = buf })

	vim.keymap.set({ "n", "i" }, "<C-p>", function()
		opts.selected_item = opts.selected_item - 1
		opts:highlight()
	end, { buffer = buf })

	vim.keymap.set({ "n", "i" }, "<CR>", function()
		local item = opts.source[opts.selected_item + 1]
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
		vim.cmd([[ quit! ]])
		vim.print(item)
		opts.on_accept(item)
	end, { buffer = buf })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = function() opts:draw() end,
	})

	opts:draw()
end
-- vim.print(require("nvim-fuzzy.fzy")("a", { "a.go", "b.go", "c.go" }))

call_find(vim.fn.expand("~/src/doctor/core"), function(files)
	vim.schedule(function()
		new_fuzzy_finder { files, function(e) vim.print(e) end }
	end)
end)

return new_fuzzy_finder
