vim.opt.runtimepath:append("~/src/nvim-fuzzy")
package.loaded["nvim-fuzzy"] = nil
package.loaded["nvim-fuzzy.files"] = nil

local make_entry = require("nvim-fuzzy.entry")
local sort_by_string_distance = require("nvim-fuzzy.ngrams")

local Fuzzy = {}

---@class Fuzzy.Entry
---@field actual string
---@field score integer
---@field display string
---@class Fuzzy.Opts
---@field source fun(query: string, collection: Fuzzy.Entry[]): Fuzzy.Entry[]
---@field transformer fun(result_item: Fuzzy.Entry): string
---@field actions table
---@param opts Fuzzy.Opts
function Fuzzy.new(opts)
	assert(opts, "opts is required")
	assert(opts.source, "opts.source is required")
	assert(type(opts.source) == "function", "opts.source must be a function")
	assert(opts.transformer, "opts.transformer is required")
	assert(type(opts.transformer) == "function", "opts.transformer must be a function")
	assert(opts.actions, "opts.actions is required")
	assert(type(opts.actions) == "table", "opts.actions must be a table")
	opts.query = opts.query or ""
	opts.sort = function(opts)
		return sort_by_string_distance(opts.query, opts.results)
	end

	---@type Fuzzy.Opts
	opts.results = {}
	opts.buf_lines = {}

	opts.last_query = ""
	local row = math.floor(vim.o.lines * 0.3)
	local col = math.floor(vim.o.columns * 0.5)
	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * 0.7)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = math.floor(vim.o.lines * 0.8),
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
	})

	local ns = vim.api.nvim_create_namespace("nvim-fuzzy")

	local function update()
		local start = vim.loop.hrtime()
		opts.source(query, opts)
		local source_elapsed = (vim.loop.hrtime() - start) / 1e6

		start = vim.loop.hrtime()
		opts.results = opts.sort(opts)
		local sort_elapsed = (vim.loop.hrtime() - start) / 1e6
		for i, v in ipairs(opts.results) do
			opts.results[i].display = opts.transformer(v)
		end
		opts.buf_lines = {}
		for _, v in ipairs(opts.results) do
			if v.actual and #v.actual > 0 then
				table.insert(opts.buf_lines, v.display)
			end
		end

		table.insert(opts.buf_lines, opts.query)
		opts.last_query = opts.query
		if not opts.selected_item then
			opts.selected_item = #opts.results - 2
		end
		print(string.format("%x %f", #opts.results, sort_elapsed))
	end

	local function draw()
		if #opts.buf_lines == 0 then
			print("No results, return")
			return
		end
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		---@type string[]

		if not opts.buf_lines or #opts.buf_lines == 0 then
			return
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.buf_lines)

		vim.api.nvim_win_set_cursor(win, { #opts.buf_lines, #opts.query + 1 })

		if opts.selected_item < 0 then
			opts.selected_item = #opts.results - 2
		end

		if opts.selected_item > #opts.results - 2 then
			opts.selected_item = #opts.results - 2
		end

		-- print(
		-- 	"Count",
		-- 	#opts.results,
		-- 	-- "selected",
		-- 	-- selected_item,
		-- 	-- "",
		-- 	-- opts.last_results_came,
		-- 	"Cost",
		-- 	opts.last_results_sorted
		-- )
		vim.hl.range(buf, ns, "Question", { opts.selected_item, 0 }, { opts.selected_item, width })
	end

	-- Initialize state
	update()
	draw()

	vim.keymap.set({ "n", "i" }, "<C-n>", function()
		opts.selected_item = opts.selected_item + 1
		draw()
	end, { buffer = buf })

	vim.keymap.set({ "n", "i" }, "<C-p>", function()
		opts.selected_item = opts.selected_item - 1
		draw()
	end, { buffer = buf })

	vim.keymap.set({ "n", "i" }, "<CR>", function()
		local item = opts.results[opts.selected_item]
		opts.actions.enter(item)
	end, { buffer = buf })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, -2, -1, false)
			opts.query = lines[1]
			if opts.query ~= opts.last_query or not opts.initialized then
				update()
				draw()
			end
		end,
	})
end
local find = require("nvim-fuzzy.find")

local files_fetched = false
Fuzzy.new({
	source = function(query, opts)
		local start = vim.loop.hrtime()
		if not files_fetched then
			find(vim.fn.expand("~/.dotfiles"), function(res)
				local results_came = (vim.loop.hrtime() - start) / 1e6
				opts.results = {}
				for _, v in ipairs(res) do
					table.insert(opts.results, make_entry(v))
				end
				files_fetched = true
			end)
		end
		opts.source_tool = (vim.loop.hrtime() - start) / 1e6
	end,

	---@param e Fuzzy.Entry
	transformer = function(e)
		return string.format("%X %s", e.score, e.actual)
	end,
	actions = {
		---@param e Fuzzy.Entry
		enter = function(e)
			print(e.actual)
		end,
	},
})
--
return Fuzzy
