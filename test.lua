-- print(#arg)
local MqttNode = require 'mqtt-node'
local node = MqttNode:new({
    clientId = 'test_id',
    lifetime = 16000,
    ip = '192.168.0.55',
    mac = 'AA:BB:CC:DD:EE:FF',
    version = '0.0.1'
})

node:setDevAttrs({
    clientId = 'test_idxx',
    lifetime = 11000,
    ip = '192.168.0.551',
    mac = 'FF:BB:CC:DD:EE:FF',
    version = '0.0.2'
})

local temp = 25
node:initResrc(3303, 0, {
    [5700] = {
        read = function (cb)
            cb(0, temp)
        end,
        write = function (val, cb)
            temp = val
            cb(0, temp)
        end
    },
    [5701] = {
        exec = function (cb)
            cb(0, temp)
        end
    },
    [5702] = {
        write = function (cb)
            cb(0, temp)
        end
    },
    [5703] = {
        a = 1,
        b = 2
    },
    [5704] = 'Hello World'
})
node:print()
node:readResrc(3303, 0, 5701, function(err, val)
    print(err)
    print(val)
end)

node:writeResrc(3303, 0, 5700, 70, function(err, val)
    print(err)
    print(val)
end)

node:readResrc(3303, 0, 5700, function(err, val)
    print(err)
    print(val)
end)

-- for k, v in pairs(node.so) do
--     print(k)
--     print(v)
--     for k1, v1 in pairs(v) do
--         print(k1)
--         print(v1)

--         for k2, v2 in pairs(v1) do
--             print(k2)
--             print(v2)
--         end

--     end
-- end

node:print()
