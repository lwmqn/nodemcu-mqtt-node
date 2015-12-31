function slashPath(path)
    local head = 1
    local tail = #path
    path = path:gsub("%.", "/")
    if (path:sub(1, 1) == '/') then
        head = 2
    end

    if (path:sub(#path, #path) == '/') then
        tail = tail - 1
    end

    return path:sub(head, tail);
end


local s = slashPath('.a.b.c.')
print(s)
