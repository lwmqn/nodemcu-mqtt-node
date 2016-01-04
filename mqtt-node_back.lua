------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENCE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
local EventEmitter = require 'lua_modules.events'
local mutils = require 'lua_modules.mutils'

--local moduleName = ...
-- _G[moduleName] = M

local MqttNode = {
    clientId = nil,
    lifetime = 86400,
    ip = nil,
    mac = nil,
    version = '0.0.1'
}

MqttNode = EventEmitter(MqttNode)

local errcode = {
    success = 0,
    notfound = 1,
    unreadable = 2,
    unwritable = 3
}

-- setmetatable(MqttNode, {
--     __call = function (_, ...) return MqttNode:new(...) end
-- })

function MqttNode:new(node)
    node = node or {}

    self.__index = self

    node.clientId = node.clientId
    node.lifetime = node.lifetime or self.lifetime
    node.ip = node.ip or self.ip
    node.mac = node.mac or self.mac
    node.version = node.version or self.version

    --node.mc = mqtt.Client("clientId", 120, "user", "password")
    node.mc = 'fake'
    node.so = { -- Default Objects
        [1] = {         -- LWM2M Object: LWM2M Server Object
            [0] = nil,              -- short server id
            [1] = node.lifetime,    -- lifetime
            [2] = 1,                -- default pmin in seconds
            [3] = 60,               -- default pmax on seconds
            [8] = {                 -- registration update trigger
                exec: function ()
                end
            }
        },
        [3] = {         -- LWM2M Object: Device
            [0] = 'freebird',   -- manuf
            [1] = 'mqtt-node',  -- model
            [4] = {             -- reboot
                exec = function ()
                end
            },
            [5] = {             -- factory reset
                exec = function ()
                end
            },
            [6] = 0,            -- available power sources
            [7] = 5000,         -- power source voltage
            [17] = 'generic',   -- device type
            [18] = 'v0.0.1',    -- hardware version
            [19] = 'v0.0.1',    -- software version
        },
        [4] = {         -- LWM2M Object: Connectivity Monitoring
            [4] = node.ip,      -- ip address
            [5] = nil           -- router ip address
        }
    }

    node._pubics = {
        register = 'register/' .. node.clientId,
        deregister = 'deregister/' .. node.clientId,
        notify = 'notify/' .. node.clientId,
        update = 'update/' .. node.clientId,
        ping = 'ping/' .. node.clientId,
        response = 'response/' .. node.clientId
    }

    node._subics = {
        register = 'register/response/' .. node.clientId,
        deregister = 'deregister/response/' .. node.clientId,
        notify = 'notify/response/' .. node.clientId,
        update = 'update/response/' .. node.clientId,
        ping = 'ping/response/' .. node.clientId,
        request = 'request/' .. node.clientId,
        announce = 'announce'
    }

    node.repAttrs = {}
    node = setmetatable(node, self)

    return node
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
    local argtbl = { ... }
    local iobj, oid, iid, resrcs

    if (#argtbl == 2) then
        oid = argtbl[1]
        resrcs = argtbl[2]
    else
        oid = argtbl[1]
        iid = argtbl[2] or nil
        resrcs = argtbl[3]
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

function MqttNode:_dumpInstance(oid, iid)
    local dump = {}
    local inst = self.so[oid][iid]

    for rid, resrc in pairs(inst) do
        self:readResrc(oid, iid, rid, function (err, val)
            dump[rid] = val
        end)
    end
    return dump
end

function MqttNode:_dumpObject(oid)
    local dump = {}
    local obj = self.so[oid]


    for iid, inst in pairs(obj) do
        dump[iid] = self:_dumpInstance(oid, iid)
    end

    return dump
end

function MqttNode:connect(url, opts)
    local mc = self.mc
    local evt
    -- opts = opts or {}
    -- local port = opts
    -- [TODO]

    -- (1) remove listeners

    -- (2) re-attch listeners
    mc:connect(host, port, secure, function (client)
        mc:on('message', function (conn, topic, data)
            data = self.decrypt(data)

            if (topic == self._subics.register) then
                evt = evt = 'reg_rsp'
            elseif (topic == self._subics.deregister) then
                evt = 'dereg_rsp'
            elseif (topic == self._subics.notify) then
                evt = 'notify_rsp'
            elseif (topic == self._subics.update) then
                evt = 'update_rsp'
            elseif (topic == self._subics.ping) then
                evt = 'ping_rsp'
            elseif (topic == self._subics.request) then
                evt = 'request'
            elseif (topic == self._subics.announce) then
                evt = 'announce'
            else
            end

            if (evt ~= nil) then
                self.emit(evt, data)
            end
            if (evt == 'reg_rsp') then
                self.emit('_reg_rsp', data)
            end
            if (evt == 'request') then
                self.emit('_request', data)
            end
        end)
    end)
end

-- -- function MqttNode:encrypt(msg)
-- --     return msg
-- -- end

-- -- function MqttNode:decrypt(msg)
-- --     return msg
-- -- end

function MqttNode:_requestMessageDispatcher(msg)
    local cmdId = msg.cmdId
    local trgType
    local reqMsgHdlr
    local rspMsg = {
            transId = msg.transId,
            cmdId = msg.cmdId,
            status =  200,
            data = nil
        }

    self:_target(oid, iid, rid)

    if (msg.oid ~= nil) then
        trgType = 'object'

        -- oid '' Root not allowed 405
        -- oid not found 404
    end

    if (msg.iid ~= nil) then
        trgType = 'instance'
        -- iid not found 404
    end

    if (msg.rid ~= nil) then
        trgType = 'resource'
        -- rid not found 404
    end

    msg.trgType = trgType

    if (cmdId == 0) then
        reqMsgHdlr = _readReqHandler
    elseif (cmdId == 1) then
        reqMsgHdlr = _writeReqHandler
    elseif (cmdId == 2) then
        reqMsgHdlr = _discoverReqHandler
    elseif (cmdId == 3) then
        reqMsgHdlr = _writeAttrsReqHandler
    elseif (cmdId == 4) then
        reqMsgHdlr = _executeReqHandler
    elseif (cmdId == 5) then
        reqMsgHdlr = _observeReqHandler
    elseif (cmdId == 6) then
        -- notify, this is not a request, do nothing
    else
        -- 400 bad request
        rspMsg.status = 400
        reqMsgHdlr = function (node, msg) {
            node.publish(node._pubics.response, rspMsg);
        };
    end
end


-- -- function MqttNode:close()

-- -- end

function MqttNode:objectList()
    local objList = {}

    for oid, obj in pairs(self.so) do
        for iid, inst in pairs(obj) do
            table.insert(objList, {
                oid = oid,
                iid = iid
            })
        end
    end

    return objList
end

function MqttNode:pubRegister(callback)
    local regPubChannel = self._pubics.register
    local regData = {
            lifetime = self.lifetime,
            objList = self.objectList(),
            ip = self.ip,
            mac = self.mac,
            version = self.version,
         }

    self:publish(regPubChannel, regData, callback)
end

function MqttNode:pubDeregister(callback)
    local deregPubChannel = self._pubics.deregister
    self:publish(deregPubChannel, { data = nil }, callback)
end

function MqttNode:pubNotify(data, callback)
    local notifyPubChannel = self._pubics.notify
    self:publish(notifyPubChannel, data, callback)
end

function MqttNode:pingServer(callback)
    local pingPubChannel = self._pubics.ping
    self:publish(pingPubChannel, { data = nil }, callback)
end

function MqttNode:pubUpdate(devAttrs, callback)
    local updatePubChannel = self._pubics.update
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    assert(devAttrs.mac == nil, "mac cannot be changed at runtime.")
    self:publish(updatePubChannel, devAttrs, callback)
end

function MqttNode:pubResponse(rsp, callback)
    local rspPubChannel = self._pubics.response
    self:publish(rspPubChannel, rsp, callback)
end

function MqttNode:publish(topic, message, qos, retain, callback)
    -- [TODO] default options?
    m:publish(topic, message, qos, retain, function (client)
        self.emit('published', {
            topic = topic,
            message = message,
            options = options
        })

        if (callback ~= nil) then
            callback()
    end)
end

-- -- function MqttNode:subscribe()

-- -- end

-- -- function MqttNode:unsubscribe()

-- -- end

-- ********************************************* --
-- **  MqttNode Request Handlers              ** --
-- ********************************************* --
function _readReqHandler(node, msg)
    local iobj
    local rspMsg = {
            transId = msg.transId,
            cmdId = msg.cmdId,
            status = 205,       -- 205: 'Content'
            data = nil
        }

    if (msg.oid == nil) then   -- Root setting is not allowed
        rspMsg.status = 400;   -- Bad Request
        node.publish(node._pubics.response, rspMsg);
        return
    end

    local nodeData = node.dump()

    if (msg.trgType === 'object') then
        rspMsg.data = nodeData.so[msg.oid]
        node.publish(node._pubics.response, rspMsg)
    elseif (msg.trgType === 'instance') then
        rspMsg.data = nodeData.so[msg.oid][msg.iid]
        node.publish(node._pubics.response, rspMsg)
    elseif (msg.trgType === 'resource') then
        rspMsg.data = nodeData.so[msg.oid][msg.iid][msg.rid]
        node.publish(node._pubics.response, rspMsg)
    end
end

function _writeReqHandler(node, msg)
    local iobj
    local rspMsg = {
            transId = msg.transId,
            cmdId = msg.cmdId,
            status = 204,    -- 204: 'Changed'
            data = nil
        };

    -- [TODO] 1. allow object and instance
    --        2. tackle access control in the near future
    if (msg.trgType === 'object') then             -- will support in the future
        rspMsg.status = 405;                    -- 405: MethodNotAllowed
        node.publish(node._pubics.response, rspMsg);
    elseif (msg.trgType === 'instance') then    -- will support in the future
        rspMsg.status = 405;                    -- 405: MethodNotAllowed
        node.publish(node._pubics.response, rspMsg);
    else if (msg.trgType === 'resource') then
        node:writeResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, resrc)
            if (err == errcode.success) then
                rspMsg.data = resrc
                node.publish(node._pubics.response, rspMsg)
            else
                -- 405
            end
        end)
    end
end
-- ********************************************* --
-- **  Utility Methods                        ** --
-- ********************************************* --

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

-- ********************************************* --
-- **  Protected Methods                      ** --
-- ********************************************* --
function MqttNode:_target(oid, iid, rid)
    local tgtype
    local target

    if (oid ~= nil) then
        tgtype = 'object'
        if (iid ~= nil) then
            tgtype = 'instance'
            if (rid ~= nil) then
                tgtype = 'resource'
            end
        end
    end

    if (tgtype == 'object') then
        target = self._dumpObject(oid)
    elseif (tgtype == 'instance') then
        target = self._dumpInstance(oid, iid)
    elseif (tgtype == 'resource') then
        self:readResrc(oid, iid, rid, function (err, val)
            target = val
        end)
    end

    if (target == nil) then
        target = '__notfound'
    end

    return tgtype, target
end

function MqttNode:getAttrs(...)
    -- args: oid, iid, rid
    local argtbl = { ... }
    local oid = argtbl[1]
    local iid = nil
    local rid = nil
    local tgtype, target
    local attr

    if (#argtbl == 3) then
        iid = argtbl[2]
        rid = argtbl[3]
    elseif (#argtbl == 2) then
        iid = argtbl[2]
    end

    tgtype, target = self:_target(oid, iid, rid)
    if (target == nil) then
        return '__notfound'
    end

    if (tgtype == 'object') then
        attr = self.repAttrs[oid]
    elseif (tgtype == 'instance') then
        attr = self.repAttrs[oid]
        if (attr ~= nil) then attr = attr[iid] end
    elseif (tgtype == 'resource') then
        attr = self.repAttrs[oid]
        if (attr ~= nil) then attr = attr[iid] end
        if (attr ~= nil) then attr = attr[rid] end
    end

    return attr
end

function MqttNode:setAttrs(...)
    -- args: oid, iid, rid, attrs
    local argtbl = { ... }
    local oid = argtbl[1]
    local iid
    local rid
    local attrs
    local tgtype

    self.repAttrs[oid] = self.repAttrs[oid] or {}

    if (#argtbl == 4) then
        iid = argtbl[2]
        rid = argtbl[3]
        attrs = argtbl[4]
    elseif (#argtbl == 3) then
        iid = argtbl[2]
        attrs = argtbl[3]
    elseif (#argtbl == 2) then
        attrs = argtbl[2]
    end

    tgtype = self:_target(oid, iid, rid)

    if (tgtype == 'object') then
        self.repAttrs[oid] = attrs
    elseif (tgtype == 'instance') then
        self.repAttrs[oid][iid] = self.repAttrs[oid][iid] or {}
        self.repAttrs[oid][iid] = attrs
    elseif (tgtype == 'resource') then
        self.repAttrs[oid][iid] = self.repAttrs[oid][iid] or {}
        self.repAttrs[oid][iid][rid] = self.repAttrs[oid][iid][rid] or {}
        self.repAttrs[oid][iid][rid] = attrs
    end
end

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
-- V setDevAttrs
-- V initResrc
-- V readResrc
-- V writeResrc
-- V dump
-- connect
-- close

-- V pubRegister
-- V pubDeregister
-- V pubNotify
-- V pingServer

-- V publish
-- subscribe
-- unsubscribe
-- --]]

function msgHandler(conn, topic, data)  -- conn is client
    local message = self:decrypt(message)
    local evt
    self.emit('message', topic, message);

    local jsonMsg = cjson.decode(message)
    local path = mutils.slashPath(topic)

    if (path == self._subics.register) then
        evt = 'reg_rsp'
    elseif (path == self._subics.deregister) then
        evt = 'dereg_rsp'
    elseif (path == self._subics.notify) then
        evt = 'notify_rsp'
    elseif (path == self._subics.update) then
        evt = 'update_rsp'
    elseif (path == self._subics.ping) then
        evt = 'ping_rsp'
    elseif (path == self._subics.request) then
        evt = 'request'
    elseif (path == self._subics.announce) then
        evt = 'announce'
    end

    if (evt ~= nil) then
        self.emit(evt, jsonMsg)
    end

    if (evt == 'request') then
        self.emit('_request', jsonMsg)
    end


end
