local function live_finder(opts)
    assert(opts)
    assert(opts[1])
    assert(opts[2])
    assert(type(opts[1]) == 'function')
    assert(type(opts[2]) == "function")
end

return live_finder
