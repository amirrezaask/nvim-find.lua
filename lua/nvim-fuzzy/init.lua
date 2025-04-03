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

	function opts.update(opts)
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

		table.insert(opts.buf_lines, opts.query) -- adds a line for prompt
		opts:draw()
	end

	function opts.draw(opts)
		if not opts.selected_item then
			opts.selected_item = 1
		end

		if opts.selected_item < 0 then
			opts.selected_item = #opts.results - 2
		end

		if opts.selected_item > #opts.results - 2 then
			opts.selected_item = 0
		end
		if #opts.buf_lines == 0 then
			print("No results, return")
		end
		vim.api.nvim_buf_clear_namespace(buf, opts.hl_ns, 0, -1)
		---@type string[]

		if not opts.buf_lines or #opts.buf_lines == 0 then
			return
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.buf_lines)

		vim.api.nvim_win_set_cursor(win, { #opts.buf_lines, #opts.query + 1 })

		-- print(string.format("%x %f", #opts.results, opts.source_elapsed or 0))
		print(opts.selected_item, opts.query)
		vim.hl.range(buf, opts.hl_ns, "Question", { opts.selected_item, 0 }, { opts.selected_item, width })
	end

	function opts.set_keymaps(opts)
		vim.keymap.set({ "n", "i" }, "<C-n>", function()
			opts.selected_item = opts.selected_item + 1
			opts:draw()
		end, { buffer = buf })

		vim.keymap.set({ "n", "i" }, "<C-p>", function()
			opts.selected_item = opts.selected_item - 1
			opts:draw()
		end, { buffer = buf })

		vim.keymap.set({ "n", "i" }, "<CR>", function()
			local item = opts.results[opts.selected_item + 2]
			opts.actions.enter(item)
		end, { buffer = buf })
	end

	function opts.setup_autocmds(opts)
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			buffer = buf,
			callback = function()
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				opts.query = lines[#opts.buf_lines]
				if #lines < #opts.buf_lines then
					opts.query = ""
				end
				if opts.query ~= opts.last_query or not opts.initialized then
					opts.last_query = opts.query
					opts:source()
				end
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
local find = require("nvim-fuzzy.find")

Fuzzy.new({
	files_fetched = false,
	source = function(opts)
		local start = vim.loop.hrtime()
		if not opts.files_fetched then
			find(vim.fn.expand("~/.dotfiles"), function(res)
				local results_came = (vim.loop.hrtime() - start) / 1e6
				opts.results = {}
				for _, v in ipairs(res) do
					table.insert(opts.results, make_entry(v))
				end
				opts.source_elapsed = (vim.loop.hrtime() - start) / 1e6
				opts.files_fetched = true
				vim.schedule(function()
					opts:update()
				end)
			end)
		else
			opts:update()
		end
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
