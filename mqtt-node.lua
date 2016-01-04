------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENCE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
local EventEmitter = require 'lua_modules.events'
local mutils = require 'lua_modules.mutils'

-- ************** Code Enumerations **************
local errcode = { success = 0, notfound = 1, unreadable = 2, unwritable = 3, timeout = 4 }
local cmdcode = { read = 0, write = 1, discover = 2, writeAttrs = 3, execute = 4, observe = 5, notify = 6 , unknown = 255 }
local trgtype = { root = 0, object = 1, instance = 2, resource = 3 }

-- ************** MqttNode Base Class  **************
local modName = ...
local MqttNode = EventEmitter({ clientId = nil, lifetime = 86400, ip = nil, mac = nil, version = '0.0.1' })
_G[modName] = MqttNode

-- ************** Constructor **************
function MqttNode:new(qnode)
    qnode = qnode or {}
    self.__index = self

    -- qnode.mac and qnode.ip are MUSTs
    assert(qnode.mac ~= nil, "mac address should be given.")
    assert(qnode.ip ~= nil, "ip address should be given.")

    if (qnode.clientId == nil) then qnode.clientId = 'qnode-' .. string.tostring(qnode.mac) end

    qnode.clientId = qnode.clientId
    qnode.lifetime = qnode.lifetime or self.lifetime
    qnode.version = qnode.version or self.version

    qnode.mc = nil
    qnode.so = {}
    self._buildDefaultSo(qnode)  -- Build Default Objects

    qnode._repAttrs = {}
    qnode._trandId = 0
    qnode._intfRspCbs = {} -- { intf = { transId = cb } }

    qnode = setmetatable(qnode, self)
    return qnode
end

-- ok
function MqttNode:setDevAttrs(devAttrs)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")

    local updated = {}
    local count = 0

    for k, v in pairs(devAttrs) do
        -- only these 3 parameters can be changed at runtime
        if (k == 'lifetime' or k == 'ip' or k == 'version') then
            if (self[k] ~= v) then
                c = c + 1
                self[k] = v
                updated[k] = v
            end
        end
    end

    if (count > 0) then self:pubUpdate(updated) end
end

-- ok
function MqttNode:initResrc(...)
    local argtbl = { ... }
    local oid, iid, resrcs

    oid = tonumber(argtbl[1]) or argtbl[1]
    if (#argtbl == 2) then
        resrcs = argtbl[2]
    else
        iid = tonumber(argtbl[2]) or argtbl[2]
        resrcs = argtbl[3]
    end

    assert(type(resrcs) == "table", "resrcs should be a table.")

    self.so[oid] = self.so[oid] or {}

    iid = iid or self:_assignIid(self.so[oid])
    iid = tonumber(iid) or iid
    -- assert(type(iid) == "number", "iid should be a number.")

    self.so[oid][iid] = self.so[oid][iid] or {}

    for rid, rval in pairs(resrcs) do self:_initResrc(oid, iid, rid, rval) end

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
        smartobj[oid] = self:_dumpObject(oid)
    end

    dump.so = smartobj
    return dump
end



function MqttNode:connect(url, opts)
    assert(_G['mqtt'] ~= nil, "mqtt module is not loaded.")
    self.mc = mqtt.Client(self.clientId, 120, opt.username, opt.password)

    local mc = self.mc
    local evt
    -- opts = opts or {}
    -- local port = opts
    -- [TODO]

    -- (1) remove listeners

    -- (2) re-attch listeners

    if (evt ~= nil) then
        self.emit(evt, jsonMsg)
    end

    if (evt == 'request') then
        self.emit('_request', jsonMsg)
    end

    mc:connect(host, port, secure, function (client)
        mc:on('message', function (conn, topic, msg)
            local rspCb
            local message = self:decrypt(msg)
            local jsonMsg = cjson.decode(message)
            local intf = mutils.slashPath(topic)

            if (intf == self._subics.register) then
                rspCb = self._getIntfCallback('register', msg.transId)
                if (msg.status == 200 or msg.status == 201) then
                    self._startLifeUpdater()
                else
                    self._stopLifeUpdater()
                end

            elseif (intf == self._subics.deregister) then
                rspCb = self._getIntfCallback('deregister', msg.transId)
            elseif (intf == self._subics.notify) then
                rspCb = self._getIntfCallback('notify', msg.transId)
            elseif (intf == self._subics.update) then
                rspCb = self._getIntfCallback('update', msg.transId)
            elseif (intf == self._subics.ping) then
                rspCb = self._getIntfCallback('ping', msg.transId)
            elseif (intf == self._subics.request) then
                -- No callback
                evt = 'request'
            elseif (intf == self._subics.announce) then
                -- No callback
                evt = 'announce'
            else
                -- evt = nil
            end

            if (rspCb ~= nil) then
                -- remove from deferCBs
                rspCb(nil, msg)
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

function MqttNode:encrypt(msg)
    return msg
end

function MqttNode:decrypt(msg)
    return msg
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
    local transId = self:_nextTransId()
    local regData = {
            lifetime = self.lifetime,
            objList = self:objectList(),
            ip = self.ip,
            mac = self.mac,
            version = self.version,
         }

    if (callback ~= nil) then self:_deferIntfCallback('register', transId, callback) end
    self:publish(regPubChannel, { transId = transId, data = regData })
end

function MqttNode:pubDeregister(callback)
    local deregPubChannel = self._pubics.deregister
    local transId = self:_nextTransId()

    if (callback ~= nil) then self:_deferIntfCallback('deregister', transId, callback) end
    self:publish(deregPubChannel, { transId = transId, data = nil })
end

function MqttNode:pubNotify(data, callback)
    local notifyPubChannel = self._pubics.notify
    local transId = self:_nextTransId()

    if (callback ~= nil) then self:_deferIntfCallback('notify', transId, callback) end
    self:publish(notifyPubChannel, { transId = transId, data = data })
end

function MqttNode:pingServer(callback)
    local pingPubChannel = self._pubics.ping
    local transId = self:_nextTransId()

    if (callback ~= nil) then self:_deferIntfCallback('ping', transId, callback) end
    self:publish(pingPubChannel, { transId = transId, data = nil })
end

function MqttNode:pubUpdate(devAttrs, callback)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    assert(devAttrs.mac == nil, "mac cannot be changed at runtime.")

    local updatePubChannel = self._pubics.update
    local transId = self:_nextTransId()

    if (callback ~= nil) then self:_deferIntfCallback('update', transId, callback) end
    self:publish(updatePubChannel, { transId = transId, data = devAttrs })
end

function MqttNode:pubResponse(rsp, callback)
    local rspPubChannel = self._pubics.response
    self:publish(rspPubChannel, rsp, callback)
end

function MqttNode:publish(topic, message, qos, retain, callback)
    if (type(message) == 'table') then
        message = cjson.encode(message)
    end

    m:publish(topic, message, qos, retain, function (client)
        self.emit('published', {
            topic = topic,
            message = message,
            options = options
        })

        if (callback ~= nil) then callback() end
    end)
end

-- -- function MqttNode:subscribe()

-- -- end

-- -- function MqttNode:unsubscribe()

-- -- end

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



function MqttNode:getAttrs(...)
    -- args: oid, iid, rid
    local argtbl = { ... }
    local oid = argtbl[1]
    local iid = nil
    local rid = nil
    local tgtype
    local target
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

    if (tgtype == trgtype.object) then
        attr = self._repAttrs[oid]
    elseif (tgtype == trgtype.instance) then
        attr = self._repAttrs[oid]
        if (attr ~= nil) then attr = attr[iid] end
    elseif (tgtype == trgtype.resource) then
        attr = self._repAttrs[oid]
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

    self._repAttrs[oid] = self._repAttrs[oid] or {}

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

    if (tgtype == trgtype.object) then
        self._repAttrs[oid] = attrs
    elseif (tgtype == trgtype.instance) then
        self._repAttrs[oid][iid] = self._repAttrs[oid][iid] or {}
        self._repAttrs[oid][iid] = attrs
    elseif (tgtype == trgtype.resource) then
        self._repAttrs[oid][iid] = self._repAttrs[oid][iid] or {}
        self._repAttrs[oid][iid][rid] = self._repAttrs[oid][iid][rid] or {}
        self._repAttrs[oid][iid][rid] = attrs
    end
end

-- ********************************************* --
-- **  Protected Methods                      ** --
-- ********************************************* --
function MqttNode:_target(oid, iid, rid)
    local tgtype
    local target

    if (oid ~= nil) then
        if (oid == '') then
            tgtype = trgtype.root
        else
            tgtype = trgtype.object         --'object'
        end
        if (iid ~= nil) then
            tgtype = trgtype.instance       -- 'instance'
            if (rid ~= nil) then
                tgtype = trgtype.resource   -- 'resource'
            end
        end
    end

    if (tgtype == trgtype.object) then
        target = self._dumpObject(oid)
    elseif (tgtype == trgtype.instance) then
        target = self._dumpInstance(oid, iid)
    elseif (tgtype == trgtype.resource) then
        self:readResrc(oid, iid, rid, function (err, val)
            target = val
        end)
    end

    if (target == nil) then
        target = '__notfound'
    end

    return tgtype, target
end

-- ok
function MqttNode:_initResrc(oid, iid, rid, value)
    local iobj = self.so[oid][iid]
    local isCb = false

    if (type(value) == 'table') then
        if (type(iobj[rid]) ~= 'table') then iobj[rid] = {} end

        if (type(value.read) == 'function') then
            iobj[rid].read = value.read
            iobj[rid]._isCallback = true
            isCb = true
        else
            assert(value.read == nil, "read should be a function or nil.")
        end

        if (type(value.write) == 'function') then
            iobj[rid].write = value.write
            iobj[rid]._isCallback = true
            isCb = true
        else
            assert(value.write == nil, "write should be a function or nil.")
        end

        if (type(value.exec) == 'function') then
            iobj[rid].exec = value.exec
            iobj[rid]._isCallback = true
            isCb = true
        else
            assert(value.exec == nil, "exec should be a function or nil.")
        end

        if (isCb == false) then iobj[rid] = value end

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
            break
        end
    end

    return i
end

function MqttNode:_isIntfCbOfTransId(intf, transId)
    local exist = false

    if (self._intfRspCbs[intf] ~= nil) then
        if (self._intfRspCbs[intf][transId] ~= nil) then exist = true end
    end
    return exist
end

function MqttNode:_deferIntfCallback(intf, transId, callback)
    qnode.intfRspCbs[intf] = qnode.intfRspCbs[intf] or {}
    qnode.intfRspCbs[intf][transId] = callback
end

function MqttNode:_getIntfCallback(intf, transId)
    local callback
    if (self._intfRspCbs[intf] ~= nil) then callback = self._intfRspCbs[intf][transId] end
    return callback
end

function MqttNode:_nextTransId(intf)
    self._trandId = self._trandId + 1
    if (self._trandId > 255) then self._trandId = 0 end

    if (intf ~= nil) then
        while self:_isIntfCbOfTransId(intf, self._trandId) do
            self._trandId = self._trandId + 1
        end
    end

    return self._trandId
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

    if (msg.oid == nil or msg.oid == '') then
        rspMsg.status = 400 -- Request Root is not allowed (400 Bad Request)
        qnode.publish(qnode._pubics.response, rspMsg)
        return
    end

    trgType, target = self:_target(msg.oid, msg.iid, msg.rid)

    if (target == '__notfound') then
        rspMsg.status = 404
        qnode.publish(qnode._pubics.response, rspMsg)
        return
    end

    msg.trgType = trgType

    if (cmdId == cmdcode.read) then
        rspMsg.status = 205 -- 205: 'Content'
        rspMsg.data = target
        qnode.publish(qnode._pubics.response, rspMsg)
    elseif (cmdId == cmdcode.write) then
        rspMsg.status = 204 -- 204: 'Changed'

        -- [TODO] 1. allow object and instance
        --        2. tackle access control in the near future
        if (trgType == trgtype.object) then          -- will support in the future
            rspMsg.status = 405;                -- 405: MethodNotAllowed
            qnode.publish(qnode._pubics.response, rspMsg)
            return
        elseif (trgType == trgtype.instance) then    -- will support in the future
            rspMsg.status = 405;                -- 405: MethodNotAllowed
            qnode.publish(qnode._pubics.response, rspMsg)
            return
        elseif (trgType == trgtype.resource) then
            if (target == '_unwritable_') then rspMsg.status = 405 end

            rspMsg.data = target
            qnode.publish(qnode._pubics.response, rspMsg)
        end

    elseif (cmdId == cmdcode.discover) then
        -- rspMsg.status = 205 -- 205: 'Content'

        -- if (msg.trgType === 'object') {
        --     attrs = _.cloneDeep(qnode.getAttrs(msg.oid));
        --     attrs.resrcList = qnode.so.resrcList(msg.oid);
        -- } else if (msg.trgType === 'instance') {
        --     attrs = _.cloneDeep(qnode.getAttrs(msg.oid, msg.iid));
        -- } else if (msg.trgType === 'resource') {
        --     attrs = _.cloneDeep(qnode.getAttrs(msg.oid, msg.iid, msg.rid));
        -- }

        -- rspMsg.data = _.omit(attrs, [ 'mute', 'lastReportedValue' ]);
        -- qnode.publish(qnode._pubics.response, rspMsg)

    elseif (cmdId == cmdcode.writeAttrs) then
        local allowedAttrs = { 'pmin', 'pmax', 'gt', 'lt', 'step', 'cancel', 'pintvl' }
        local badAttr = false

        rspMsg.status = 204 -- 204: 'Changed'
        if (msg.attrs ~= 'table') then
            rspMsg.status = 400 -- 400: 'BadRequest'
        else
            -- [TODO] check bad attr key : 400
        end

        if (trgType == trgtype.object) then
            if (msg.attrs.cancel ~= nil) then
                 msg.attrs.cancel = true
            end
            qnode:setAttrs(msg.oid, msg.attrs)
        elseif (trgType == trgtype.instance) then
            if (msg.attrs.cancel ~= nil) then
                 msg.attrs.cancel = true
            end
            qnode:setAttrs(msg.oid, msg.iid, msg.attrs)
        elseif (trgType == trgtype.resource) then
            if (msg.attrs.cancel == true) then
                 qnode.disableReport(msg.oid, msg.iid, msg.rid)
            end
            qnode:setAttrs(msg.oid, msg.iid, msg.rid, msg.attrs)
        end

        qnode.publish(qnode._pubics.response, rspMsg);

    elseif (cmdId == cmdcode.execute) then
        rspMsg.status = 204 -- 204: 'Changed'

        if (trgType ~= trgtype.resource) then
            rspMsg.status = 405;    -- Method Not Allowed
            qnode.publish(qnode._pubics.response, rspMsg)
            return
        else
            -- [TODO]
            -- qnode.execResrc(msg.rid, msg.data, function (err, rsp) {
            --     rspMsg = _.assign(rspMsg, rsp)
            --     qnode.publish(qnode._pubics.response, rspMsg)
            -- })
        end

    elseif (cmdId == cmdcode.observe) then
        rspMsg.status = 205 -- 205: 'Content'
        if (trgType == trgtype.object) then
             rspMsg.status = 405 -- [TODO] will support in the future
        elseif (trgType == trgtype.instance) then
             rspMsg.status = 405 -- [TODO] will support in the future
        elseif (trgType == trgtype.resource) then
            qnode.enableReport(msg.oid, msg.iid, msg.rid);
        end
        qnode.publish(qnode._pubics.response, rspMsg)
    elseif (cmdId == cmdcode.notify) then
        -- notify, this is not a request, do nothing
    else
        rspMsg.status = 400 -- 400 bad request
        qnode.publish(qnode._pubics.response, rspMsg)
    end
end

function MqttNode:_buildDefaultSo()
    self.so = self.so or {}

    -- Add Default Objects
    -- LWM2M Object: LWM2M Server Object
    self.so[1] = {
        [0] = nil,              -- short server id
        [1] = self.lifetime,    -- lifetime
        [2] = 1,                -- default pmin in seconds
        [3] = 60,               -- default pmax on seconds
        [8] = {                 -- registration update trigger
            exec: function ()
            end
        }
    }
    -- LWM2M Object: Device
    self.so[3] = {
        [0] = 'freebird',       -- manuf
        [1] = 'mqtt-node',      -- model
        [4] = {                 -- reboot
            exec = function ()
                node.restart()
            end
        },
        [5] = {                 -- factory reset
            exec = function ()
                -- [TODO]
            end
        },
        [6] = 0,                -- available power sources
        [7] = 5000,             -- power source voltage
        [17] = 'generic',       -- device type
        [18] = 'v0.0.1',        -- hardware version
        [19] = 'v0.0.1',        -- software version
    }
    -- LWM2M Object: Connectivity Monitoring
    self.so[4] = {
        [4] = self.ip,          -- ip address
        [5] = nil               -- router ip address
    }
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
    -- node._pubics = {
    --     register = 'register/' .. node.clientId,
    --     deregister = 'deregister/' .. node.clientId,
    --     notify = 'notify/' .. node.clientId,
    --     update = 'update/' .. node.clientId,
    --     ping = 'ping/' .. node.clientId,
    --     response = 'response/' .. node.clientId
    -- }

    -- node._subics = {
    --     register = 'register/response/' .. node.clientId,
    --     deregister = 'deregister/response/' .. node.clientId,
    --     notify = 'notify/response/' .. node.clientId,
    --     update = 'update/response/' .. node.clientId,
    --     ping = 'ping/response/' .. node.clientId,
    --     request = 'request/' .. node.clientId,
    --     announce = 'announce'
    -- }