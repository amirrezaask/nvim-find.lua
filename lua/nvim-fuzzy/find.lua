local M = {}

local uv = vim.loop

return function(path, callback)
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
		if code == 0 then
			callback(results)
		end
	end)

	uv.read_start(stderr, function(err, data)
		if err then
			print("stderr ", err)
			return
		end
		if data then
			print("stderr ", data)
		end
	end)

	uv.read_start(stdout, function(err, data)
		if err then
			vim.schedule(function()
				print(err)
			end)
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
