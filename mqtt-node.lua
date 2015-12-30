------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENCE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
-- local EventEmitter = require 'events'

--local moduleName = ...
-- _G[moduleName] = M

local MqttNode = {
    clientId = nil,
    lifetime = 86400,
    ip = nil,
    mac = nil,
    version = '0.0.01'
}

local errcode = {
    success = 0,
    notfound = 1,
    unreadable = 2,
    unwritable = 3
}

function MqttNode:new(info)
    info = info or {}

    self.__index = self

    info.clientId = info.clientId
    info.lifetime = info.lifetime or 86400
    info.ip = info.ip or nil
    info.mac = info.mac or nil
    info.version = info.version or '0.0.1'

    --info.mc = mqtt.Client("clientId", 120, "user", "password")
    info.mc = 'fake'
    info.so = {}

    info._pubics = {
        register = 'register/' .. info.clientId,
        deregister = 'deregister/' .. info.clientId,
        notify = 'notify/' .. info.clientId,
        update = 'update/' .. info.clientId,
        ping = 'ping/' .. info.clientId,
        response = 'response/' .. info.clientId
    }

    info._subics = {
        register = 'register/response/' .. info.clientId,
        deregister = 'deregister/response/' .. info.clientId,
        notify = 'notify/response/' .. info.clientId,
        update = 'update/response/' .. info.clientId,
        ping = 'ping/response/' .. info.clientId,
        request = 'request/' .. info.clientId,
        announce = 'announce'
    };

    return setmetatable(info, self)
end

-- [TODO] check update
function MqttNode:setDevAttrs(devAttrs)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    for k, v in pairs(devAttrs) do
        -- only these 3 parameters can be changed at runtime
        if (k == 'lifetime' or k == 'ip' or k == 'version') then
            self[k] = v
        end
    end
end

function MqttNode:initResrc(...)
    local iobj, oid, iid, resrcs

    if (#arg == 2) then
        oid = arg[1]
        resrcs = arg[2]
    else
        oid = arg[1]
        iid = arg[2] or nil
        resrcs = arg[3]
    end

    assert(type(resrcs) == "table", "resrcs should be a table.")

    self.so[oid] = self.so[oid] or {}

    iid = iid or self:_assignIid(self.so[oid])
    assert(type(iid) == "number", "iid should be a number.")

    if (self.so[oid][iid] == nil) then
        self.so[oid][iid] = {}
    end

    iobj = self.so[oid][iid]

    for rid, rval in pairs(resrcs) do
        self:_initResrc(oid, iid, rid, rval)
    end

    return self
end

-- [TODO] check report
function MqttNode:readResrc(oid, iid, rid, callback)
    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, nil)
    else
        local resrc = self.so[oid][iid][rid]
        if (type(resrc) == 'table') then
            if (resrc._isCallback == true) then
                if (type(resrc.read) == 'function') then
                    resrc.read(callback)
                elseif (type(resrc.exec) == 'function') then
                    callback(errcode.unreadable, '_exec_')
                else
                    callback(errcode.unreadable, '_unreadable_')
                end
            else
                callback(errcode.success, resrc)
            end
        elseif (type(resrc) == 'function' or type(resrc) == 'thread') then
            callback(errcode.unreadable, nil)
        else
            callback(errcode.success, resrc)
        end
    end
end

-- [TODO] check report
function MqttNode:writeResrc(oid, iid, rid, value, callback)
    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, nil)
    else
        local resrc = self.so[oid][iid][rid]
        if (type(resrc) == 'table') then
            if (resrc._isCallback) then
                if (type(resrc.write) == 'function') then
                    resrc.write(value, callback)
                else
                    callback(errcode.unwritable, nil)
                end
            else
                resrc = value
                callback(errcode.success, resrc)
            end
        elseif (type(resrc) == 'function' or type(resrc) == 'thread') then
            callback(errcode.unwritable, nil)
        else
            resrc = value
            callback(errcode.success, resrc)
        end
    end
end

function MqttNode:dump()
    local dump = {}
    local smartobj = {}

    dump.clientId = self.clientId
    dump.lifetime = self.lifetime
    dump.ip = self.ip
    dump.mac = self.mac
    dump.version = self.version

    for oid, obj in pairs(self.so) do
        smartobj[oid] = {}
        for iid, inst in pairs(obj) do
            smartobj[oid][iid] = {}
            for rid, resrc in pairs(inst) do
                self:readResrc(oid, iid, rid, function (err, val)
                    smartobj[oid][iid][rid] = val
                end)
            end
        end
    end

    dump.so = smartobj
    return dump
end


-- -- function MqttNode:connect(url, opts)
-- --     -- opts = opts or {}
-- --     -- local port = opts
-- --     self.mc.connect(host, port, secure, function ()

-- --     end)
-- -- end

-- -- function MqttNode:encrypt(msg)
-- --     return msg
-- -- end

-- -- function MqttNode:decrypt(msg)
-- --     return msg
-- -- end




-- -- function MqttNode:close()

-- -- end

-- -- function MqttNode:pubRegister()

-- -- end

-- -- function MqttNode:pubDeregister()

-- -- end

-- -- function MqttNode:pubNotify()

-- -- end

-- -- function MqttNode:pingServer()

-- -- end

-- -- function MqttNode:publish()

-- -- end

-- -- function MqttNode:subscribe()

-- -- end

-- -- function MqttNode:unsubscribe()

-- -- end

-- [[ *********************************************
--   **  Utility Methods                         **
--   ********************************************** ]]

function MqttNode:print()
    local data = self:dump()
    local s = '{\n'
    s = s .. string.rep('    ', 1) .. 'clientId: ' .. data.clientId .. ',\n'
    s = s .. string.rep('    ', 1) .. 'lifetime: ' .. data.lifetime .. ',\n'
    s = s .. string.rep('    ', 1) .. 'ip: ' .. data.ip .. ',\n'
    s = s .. string.rep('    ', 1) .. 'mac: ' .. data.mac .. ',\n'
    s = s .. string.rep('    ', 1) .. 'so: {\n'

    for oid, inst in pairs(data.so) do
        s = s .. string.rep('    ', 2) .. oid .. ': {\n'
        for iid, resrcs in pairs(data.so[oid]) do
            s = s .. string.rep('    ', 3) .. iid .. ': {\n'
            for rid, r in pairs(data.so[oid][iid]) do
                s = s .. string.rep('    ', 4) .. rid .. ': ' .. tostring(r) .. ',\n'
            end
            s = s .. string.rep('    ', 3) .. '},\n'
        end
        s = s .. string.rep('    ', 2) .. '},\n'
    end
    s = s .. string.rep('    ', 1) .. '}\n'
    s = s .. '}\n'
    print(s)
end

-- [[ *********************************************
--    **  Protected Methods                      **
--   ********************************************** ]]
function MqttNode:_initResrc(oid, iid, rid, value)
    local iobj = self.so[oid][iid]
    local isCb = false

    if (type(value) == 'table') then
        iobj[rid] = iobj[rid] or {}

        if (type(value.read) == 'function') then
            iobj[rid].read = value.read
            iobj[rid]._isCallback = true
            isCb = true
        elseif (value.read ~= nil) then
            error("read should be a function.")
        end

        if (type(value.write) == 'function') then
            iobj[rid].write = value.write
            iobj[rid]._isCallback = true
            isCb = true
        elseif (value.write ~= nil) then
            error("write should be a function.")
        end

        if (type(value.exec) == 'function') then
            iobj[rid].exec = value.exec
            iobj[rid]._isCallback = true
            isCb = true
        elseif (value.exec ~= nil) then
            error("exec should be a function.")
        end

        if (isCb == false) then
            iobj[rid] = value
        end

    elseif (type(value) ~= 'function') then
        iobj[rid] = value
    else
        iobj[rid] = nil
    end
end

function MqttNode:_assignIid(objTbl)
    local i = 0
    while i <= 255 do
        if (objTbl[i] ~= nil) then
            i = i + 1
        else
            break;
        end
    end

    return i
end

return MqttNode
-- --[[
-- APIs

-- new MqttNode
-- setDevAttrs
-- initResrc
-- readResrc
-- writeResrc

-- connect
-- close

-- pubRegister
-- pubDeregister
-- pubNotify
-- pingServer

-- publish
-- subscribe
-- unsubscribe
-- --]]

