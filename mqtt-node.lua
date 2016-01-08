------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENSE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
local EventEmitter = require 'lua_modules.events'
local timer = require 'lua_modules.timer'
local mutils = require 'lua_modules.mutils'

-- ************** Code Enumerations **************
local errcode = { success = 0, notfound = 1, unreadable = 2, unwritable = 3, timeout = 4 }
local cmdcode = { read = 0, write = 1, discover = 2, writeAttrs = 3, execute = 4, observe = 5, notify = 6 , unknown = 255 }
local trgtype = { root = 0, object = 1, instance = 2, resource = 3 }

-- ************** MqttNode Base Class  **************
local MqttNode = EventEmitter({
    clientId = nil, lifetime = 86400, ip = nil, mac = nil, version = '0.0.1'
})

local modName = ...
_G[modName] = MqttNode

-- ************** Constructor **************
function MqttNode:new(qnode)
    qnode = qnode or {}
    self.__index = self

    -- qnode.mac and qnode.ip are MUSTs
    assert(qnode.mac ~= nil, "mac address should be given.")
    assert(qnode.ip ~= nil, "ip address should be given.")

    if (qnode.clientId == nil) then qnode.clientId = 'qnode-' .. tostring(qnode.mac) end

    qnode.clientId = qnode.clientId
    qnode.lifetime = qnode.lifetime or self.lifetime
    qnode.version = qnode.version or self.version

    qnode.mc = nil
    qnode.so = {}
    self:_buildDefaultSo(qnode)  -- Build Default Objects

    qnode._repAttrs = {}
    qnode._trandId = 0
    qnode._intfRspCbs = {} -- { intf = { transId = cb } }
    qnode._lifeUpdater = nil

    qnode = setmetatable(qnode, self)
    return qnode
end

-- ok
function MqttNode:setDevAttrs(devAttrs)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    local updated, count= {}, 0

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
-- 1st ok
function MqttNode:readResrc(oid, iid, rid, callback)
    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, nil)
    else
        local resrc = self.so[oid][iid][rid]
        if (type(resrc) == 'table') then
            if (resrc._isCallback == true) then
                if (type(resrc.read) == 'function') then resrc.read(callback)
                elseif (type(resrc.exec) == 'function') then callback(errcode.unreadable, '_exec_')
                else callback(errcode.unreadable, '_unreadable_') end
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
-- ok
function MqttNode:writeResrc(oid, iid, rid, value, callback)
    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, nil)
    else
        local resrc = self.so[oid][iid][rid]
        if (type(resrc) == 'table') then
            if (resrc._isCallback) then
                if (type(resrc.write) == 'function') then resrc.write(value, callback)
                else callback(errcode.unwritable, nil) end
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

function MqttNode:execResrc(oid, iid, rid, args, callback)
    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, { status = 404 })
    else
        local resrc = self.so[oid][iid][rid]

        if (type(resrc) ~= 'table' or type(resrc.exec) ~= 'function') then
            callback(errcode.notfound, { status = 405 })
        else
            resrc.exec(args, callback)
        end
    end
end

-- ok
function MqttNode:dump()
    local dump = { so = { } }

    dump.clientId = self.clientId
    dump.lifetime = self.lifetime
    dump.ip = self.ip
    dump.mac = self.mac
    dump.version = self.version
    for oid, obj in pairs(self.so) do dump.so[oid] = self:_dumpObject(oid) end

    return dump
end

-- ok
function MqttNode:objectList()
    local objList = {}

    for oid, obj in pairs(self.so) do
        for iid, inst in pairs(obj) do table.insert(objList, { oid = oid, iid = iid }) end
    end

    return objList
end

-- ok
function MqttNode:encrypt(msg)
    return msg
end

-- ok
function MqttNode:decrypt(msg)
    return msg
end

function MqttNode:resrcList(oid)
    local obj = self.so[oid]
    local resrcList = {}

    if (type(obj) == 'table') then
        for iid, resrcs in pairs(obj) do
            resrcList[iid] = resrcList[iid] or {}
            for rid, r in resrcs do table.insert(resrcList[iid], rid) end
        end
    end
    return resrcList
end

function MqttNode:_requestHandler(msg)
    local rsp = { transId = msg.transId, cmdId = msg.cmdId, status = 200, data = nil }
    local tgtype, target = self:_target(msg.oid, msg.iid, msg.rid)

    if (tgtype == trgtype.root or msg.oid == nil) then
        rsp.status = 400    -- Request Root is not allowed (400 Bad Request)
        self:pubResponse(rsp)
        return
    end

    if (target == '__notfound') then
        rsp.status = 404
        self:pubResponse(rsp)
        return
    end

    if (msg.cmdId == cmdcode.read) then

        if (tgtype == trgtype.resource and target == '_unreadable_') then
            rsp.status = 405 -- 405: 'MethodNotAllowed'
        else
            rsp.status = 205 -- 205: 'Content'
        end
        rsp.data = target
        self:pubResponse(rsp)

    elseif (msg.cmdId == cmdcode.write) then

        -- [TODO] 1. allow object and instance
        --        2. tackle access control in the near future
        if (tgtype == trgtype.object or tgtype == trgtype.instance) then    -- will support in the future
            rsp.status = 405;                -- 405: 'MethodNotAllowed'
            self:pubResponse(rsp)
        elseif (tgtype == trgtype.resource) then

            self:writeResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, val)
                if (err == errcode.unwritable) then
                    rsp.status = 405
                else
                    rsp.status = 204 -- 204: 'Changed'
                    rsp.data = val
                end
                self:pubResponse(rsp)
            end)
        end

    elseif (cmdId == cmdcode.discover) then

        local attrs

        if (tgtype == trgtype.object) then
            attrs = self:getAttrs(msg.oid)
            attrs = attrs or {}
            attrs.resrcList = self:resrcList(msg.oid)
        elseif (tgtype == trgtype.instance) then
            attrs = self:getAttrs(msg.oid, msg.iid)
        elseif (tgtype == trgtype.resource) then
            attrs = self:getAttrs(msg.oid, msg.iid, msg.rid)
        end

        rsp.status = 205    -- 205: 'Content'
        rsp.data = attrs
        self:pubResponse(rsp)

    elseif (cmdId == cmdcode.writeAttrs) then

        local badAttr = false
        local allowedAttrsMock = {
            pmin = true, pmax = true, gt = true, lt = true,
            step = true, cancel = true, pintvl = true
        }

        if (msg.attrs ~= 'table') then
            rsp.status = 400    -- 400: 'BadRequest'
            self:pubResponse(rsp)
            return
        else
            -- check bad attr key : 400
            for k, v in pairs(msg.attrs) do
                if (allowedAttrsMock[k] ~= true) then badAttr = badAttr or true end
            end

            if (badAttr == true) then
                rsp.status = 400    -- 400: 'BadRequest'
                self:pubResponse(rsp)
                return
            end
        end

        if (tgtype == trgtype.object) then
            -- always avoid report, support in future
            if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end
            -- [TODO] should be partially set?
            self:setAttrs(msg.oid, msg.attrs)
        elseif (tgtype == trgtype.instance) then
            -- always avoid report, support in future
            if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end
            -- [TODO] should be partially set?
            self:setAttrs(msg.oid, msg.iid, msg.attrs)
        elseif (tgtype == trgtype.resource) then
            if (msg.attrs.cancel) then self:disableReport(msg.oid, msg.iid, msg.rid) end
            -- [TODO] should be partially set?
            self:setAttrs(msg.oid, msg.iid, msg.rid, msg.attrs)
        end

        rsp.status = 204 -- 204: 'Changed'
        self:pubResponse(rsp)

    elseif (cmdId == cmdcode.execute) then

        if (tgtype ~= trgtype.resource) then
            rsp.status = 405    -- Method Not Allowed
            self:pubResponse(rsp)
        else
            rsp.status = 204    -- 204: 'Changed'
            self:execResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, execRsp)
                for k, v in pairs(execRsp) do rsp[k] = v end
                self:pubResponse(rsp)
            end)
        end

    elseif (cmdId == cmdcode.observe) then

        rsp.status = 205        -- 205: 'Content'

        if (tgtype == trgtype.object or tgtype == trgtype.instance) then
             rsp.status = 405   -- [TODO] will support in the future
        elseif (tgtype == trgtype.resource) then
            self:enableReport(msg.oid, msg.iid, msg.rid)
        end
        self:pubResponse(rsp)

    elseif (cmdId == cmdcode.notify) then
        -- notify, this is not a request, do nothing
        return
    else
        -- unknown request
        rsp.status = 400        -- 400 bad request
        self:pubResponse(rsp)
    end
end

function MqttNode:_rawMessageHandler(conn, topic, message)
    local rspCb, strmsg, jmsg
    local intf = mutils.slashPath(topic)

    strmsg = self:decrypt(message)
    -- emit raw message out
    self.emit('message', strmsg)

    if (strmsg:sub(1, 1) == '{' and strmsg:sub(-1) == '}') then
        jmsg = cjson.decode(strmsg) -- decode to json msg
    end

    if (intf == self._subics.register) then
        -- get register response
        rspCb = self:_getIntfCallback('register', jmsg.transId)
        if (jmsg.status == 200 or jmsg.status == 201) then
            self:_startLifeUpdater()
        else
            self:_stopLifeUpdater()
        end

    elseif (intf == self._subics.deregister) then
        -- get deregister response
        rspCb = self:_getIntfCallback('deregister', jmsg.transId)

    elseif (intf == self._subics.notify) then
        -- get notify response
        rspCb = self:_getIntfCallback('notify', jmsg.transId)

    elseif (intf == self._subics.update) then
        -- get update response
        rspCb = self:_getIntfCallback('update', jmsg.transId)

    elseif (intf == self._subics.ping) then
        -- get ping response
        rspCb = self:_getIntfCallback('ping', jmsg.transId)

    elseif (intf == self._subics.request) then
        -- No callback
        evt = 'request'
        self:_requestHandler(jmsg)
    elseif (intf == self._subics.announce) then
        -- No callback
        evt = 'announce'
        jmsg = strmsg
    end

    if (rspCb ~= nil) then
        self:_rmIntfCallback(intf, jmsg.transId) -- remove from deferCBs
        rspCb(nil, jmsg)
    end

    if (evt ~= nil) then self:emit(evt, jmsg) end
end

function MqttNode:connect(url, opts)
    assert(_G['mqtt'] ~= nil, "mqtt module is not loaded.")
    opts = opts or {}
    opts.username = opts.username or 'freebird'
    opts.password = opts.password or 'skynyrd'
    opts.keepalive = opts.keepalive or 120
    opts.port = opts.port or 1883
    opts.secure = opts.secure or 0

    if (self.mc) then
        self.mc:close()
    else
        self.mc = mqtt.Client(self.clientId, opts.keepalive, opts.username, opts.password, opt.cleansession)
    end

    local mc = self.mc

    mc:connect(url, opts.port, opts.secure, function (client)
        mc:on('message', function (conn, topic, msg)
            self:_rawMessageHandler(conn, topic, msg)
        end)
    end)
end

-- -- function MqttNode:close()

-- -- end

function MqttNode:pubRegister(callback)
    local regPubChannel = self._pubics.register
    local regData = {
            transId = self:_nextTransId(),
            lifetime = self.lifetime,
            objList = self:objectList(),
            ip = self.ip,
            mac = self.mac,
            version = self.version,
         }

    if (callback ~= nil) then self:_deferIntfCallback('register', transId, callback) end
    self:publish(regPubChannel, regData)
end

function MqttNode:pubDeregister(callback)
    local deregPubChannel = self._pubics.deregister

    if (callback ~= nil) then self:_deferIntfCallback('deregister', transId, callback) end
    self:publish(deregPubChannel, { transId = self:_nextTransId(), data = nil })
end

function MqttNode:pubNotify(data, callback)
    local notifyPubChannel = self._pubics.notify
    data.transId = self:_nextTransId()

    self:_deferIntfCallback('notify', transId, function (err, rsp)
        if (rsp.cancel) then self:disableReport(data.oid, data.iid, data.rid) end
        if (callback ~= nil) then callback(err, rsp) end
    end)

    self:publish(notifyPubChannel, data)
end

function MqttNode:pingServer(callback)
    local pingPubChannel = self._pubics.ping

    if (callback ~= nil) then self:_deferIntfCallback('ping', transId, callback) end
    self:publish(pingPubChannel, { transId = self:_nextTransId(), data = nil })
end

function MqttNode:pubUpdate(devAttrs, callback)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    assert(devAttrs.mac == nil, "mac cannot be changed at runtime.")

    local updatePubChannel = self._pubics.update

    devAttrs.transId = self:_nextTransId()
    if (callback ~= nil) then self:_deferIntfCallback('update', transId, callback) end
    self:publish(updatePubChannel, devAttrs)
end

function MqttNode:pubResponse(rsp, callback)
    local rspPubChannel = self._pubics.response
    self:publish(rspPubChannel, rsp, callback)
end

function MqttNode:publish(topic, message, qos, retain, callback)
    if (type(message) == 'table') then message = cjson.encode(message) end
    local encrypted = self:encrypt(message)

    m:publish(topic, encrypted, qos, retain, function (client)
        self:emit('published', { topic = topic, message = message, options = options })
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

--[[
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
-- ]]

-- [TODO] use _find inside
function MqttNode:getAttrs(...)
    -- args: oid, iid, rid
    local argtbl = {...}
    local oid = argtbl[1]
    local iid, rid, tgtype, target, attrs

    tgtype, target = self:_target(...)
    if (target == '__notfound') then return '__notfound' end

    if (#argtbl == 3) then
        iid, rid = argtbl[2], argtbl[3]
    elseif (#argtbl == 2) then
        iid = argtbl[2]
    end

    if (tgtype == trgtype.object) then
        attrs = self._repAttrs[oid]
    elseif (tgtype == trgtype.instance) then
        attrs = self._repAttrs[oid]
        if (attrs ~= nil) then attrs = attrs[iid] end
    elseif (tgtype == trgtype.resource) then
        attr = self._repAttrs[oid]
        if (attrs ~= nil) then attrs = attrs[iid] end
        if (attrs ~= nil) then attrs = attrs[rid] end
    end

    return attrs
end -- nil is not set, __notfound is no such thing

-- ok
function MqttNode:setAttrs(...)
    -- args: oid, iid, rid, attrs
    local argtbl = { ... }
    local oid = argtbl[1]
    local iid, rid, tgtype, target, attrs

    if (#argtbl == 4) then
        iid, rid, attrs = argtbl[2], argtbl[3], argtbl[4]
    elseif (#argtbl == 3) then
        iid, attrs = argtbl[2], argtbl[3]
    elseif (#argtbl == 2) then
        attrs = argtbl[2]
    end

    tgtype, target = self:_target(oid, iid, rid)
    if (target == '__notfound') then return '__notfound' end

    self._repAttrs[oid] = self._repAttrs[oid] or {}

    if (tgtype == trgtype.object) then
        self._repAttrs[oid] = attrs
    elseif (tgtype == trgtype.instance) then
        self._repAttrs[oid][iid] = attrs
    elseif (tgtype == trgtype.resource) then
        self._repAttrs[oid][iid] = self._repAttrs[oid][iid] or {}
        self._repAttrs[oid][iid][rid] = attrs
    end
end

-- ********************************************* --
-- **  Protected Methods                      ** --
-- ********************************************* --
-- ok
function MqttNode:_target(oid, iid, rid)
    local tgtype, target

    if (oid ~= nil) then
        if (oid == '') then tgtype = trgtype.root
        else tgtype = trgtype.object end    --'object'

        if (iid ~= nil) then
            tgtype = trgtype.instance       -- 'instance'
            if (rid ~= nil) then tgtype = trgtype.resource end  -- 'resource'
        end
    end

    if (tgtype == trgtype.object) then target = self:_dumpObject(oid)
    elseif (tgtype == trgtype.instance) then target = self:_dumpInstance(oid, iid)
    elseif (tgtype == trgtype.resource) then self:readResrc(oid, iid, rid, function (err, val) target = val end)
    end

    if (target == nil) then target = '__notfound' end

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

-- ok
function MqttNode:_assignIid(objTbl)
    local i = 0
    while objTbl[i] do i = i + 1 end
    return i
end

-- ok
function MqttNode:_deferIntfCallback(intf, transId, callback)
    self.intfRspCbs[intf] = self.intfRspCbs[intf] or {}
    self.intfRspCbs[intf][transId] = callback
end

-- ok
function MqttNode:_getIntfCallback(intf, transId)
    if (self._intfRspCbs[intf] ~= nil) then return self._intfRspCbs[intf][transId] end
    return nil
end

-- ok
function MqttNode:_rmIntfCallback(intf, transId)
    if (self._intfRspCbs[intf] ~= nil) then self._intfRspCbs[intf][transId] = nil end
end

-- ok
function MqttNode:_nextTransId(intf)
    self._trandId = self._trandId + 1
    if (self._trandId > 255) then self._trandId = 0 end

    if (intf ~= nil) then
        while self:_getIntfCallback(intf, self._trandId) do self._trandId = self._trandId + 1 end
    end
    return self._trandId
end

-- ok
function MqttNode:_dumpInstance(oid, iid)
    local dump, inst = {}, self.so[oid][iid]

    if (inst == nil) then return nil end
    for rid, resrc in pairs(inst) do
        self:readResrc(oid, iid, rid, function (err, val) dump[rid] = val end)
    end
    return dump
end

-- ok
function MqttNode:_dumpObject(oid)
    local dump, obj = {}, self.so[oid]

    if (obj == nil) then return nil end
    for iid, inst in pairs(obj) do dump[iid] = self:_dumpInstance(oid, iid) end
    return dump
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
            exec = function ()
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

function MqttNode:_startLifeUpdater()
    local lfCountSecs, checkPoint = 0

    if (self.lifetime > 43199) then  checkPoint = 43200 end     -- 12 hours

    if (self._lifeUpdater ~= nil) then
        timer.clearInterval(self._lifeUpdater)
        self._lifeUpdater = nil
    end

    self.lifeUpdater = timer.setInterval(function ()
        lfCountSecs = lfCountSecs + 1
        if (lfCountSecs == checkPoint) then
            self:pubUpdate({ lifetime = self.lifetime })
            self:_startLifeUpdater()
        end
    end, 1000)
end

function MqttNode:_stopLifeUpdater()
    if (self._lifeUpdater ~= nil) then
        timer.clearInterval(self._lifeUpdater)
        self._lifeUpdater = nil
    end
end

function MqttNode:_checkAndReportResrc(oid, iid, rid, currVal)
    local resrcAttrs = self:getAttrs(oid, iid, rid)

    if (resrcAttrs ~= nil) then return false end    -- no attrs were set
    if (resrcAttrs.cancel or resrcAttrs.mute) then return false end

    if (self:_isResrcNeedReport(oid, iid, rid, currVal)) then
        resrcAttrs.lastRpVal = currVal
        self:pubNotify({ oid = oid, iid = iid, rid = rid, data = currVal })
        return true
    end

    return false
end

function MqttNode:_isResrcNeedReport(oid, iid, rid, currVal)
    local resrcAttrs, needReport = self:getAttrs(oid, iid, rid), false
    local lastRpVal, gt, lt, step

    if (resrcAttrs == nil) then return false end
    -- .report() has taclked the lastReportValue assigment
    lastRpVal = resrcAttrs.lastRpVal
    gt = resrcAttrs.gt
    lt = resrcAttrs.lt
    step = resrcAttrs.step

    if (type(currVal) == 'table') then
        if (type(lastRpVal) == 'table') then
            for k, v in pairs(currVal) do
                if (v ~= lastRpVal[k]) then needReport = true end
            end
        else
            needReport = true
        end

    elseif (type(currVal) ~= 'number') then
        if (lastRpVal ~= currVal) then needReport = true end
    else
        if (type(gt) == 'number' and type(lt) == 'number' and lt > gt) then
            if (lastRpVal ~= currVal and currVal > gt and currVal < lt) then needReport = true end
        else
            if (type(gt) == 'number' and lastRpVal ~= currVal and currVal > gt) then needReport = true end
            if (type(lt) == 'number' and lastRpVal ~= currVal and currVal < lt) then needReport = true end
        end

        if (type(step) == 'number') then
            if (math.abs(currVal - lastRpVal) > step) then needReport = true end
        end
    end

    return needReport
end

-- [TODO] need check
function MqttNode:enableReport(oid, iid, rid, attrs)
    local resrcAttrs, resrcReporter, pminMs, pmaxMs
    local tgtype, target = self:_target(oid, iid, rid)

    if (target == '__notfound') then return false end

    resrcAttrs = self:getAttrs(oid, iid, rid)

    if (resrcAttrs == nil) then resrcAttrs = self:_findAttrs(oid, iid, rid) end

    resrcAttrs.cancel = false
    resrcAttrs.mute = true

    -- [TODO] pmin and pmax are MUSTs
    pminMs = resrcAttrs.pmin * 1000 or 0
    pmaxMs = resrcAttrs.pmax * 1000 or 600000

    -- reporter place holder
    self.reporters[oid] = self.reporters[oid] or {}
    self.reporters[oid][iid] = self.reporters[oid][iid] or {}
    self.reporters[oid][iid][rid] = { minRep = nil, maxRep = nil, poller = nil }
    resrcReporter = self.reporters[oid][iid][rid]

    -- mute is use to control the poller
    resrcReporter.minRep = timer.setTimeout(function ()
        if (pminMs == 0) then   -- if no pmin, just report at pmax triggered
            resrcAttrs.mute = false
        else
            self:readResrc(oid, iid, rid, function (err, val)
                resrcAttrs.mute = false
                self:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
            end)
        end
    end, pminMs)

    resrcReporter.maxRep = timer.setInterval(function ()
        resrcAttrs.mute = true

        self:readResrc(oid, iid, rid, function (err, val)
            resrcAttrs.mute = false
            self:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
        end)

        resrcReporter.minRep = nil
        resrcReporter.minRep = timer.setTimeout(function ()
            if (pminMs == 0) then --  if no pmin, just report at pmax triggered
                resrcAttrs.mute = false;
            else
                self:readResrc(oid, iid, rid, function (err, val)
                    resrcAttrs.mute = false
                    self:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
                end)
            end
        end, pminMs)
    end, pmaxMs)

    return true
end

-- [TODO] need check
function MqttNode:disableReport(oid, iid, rid)
    local resrcAttrs, resrcReporter = self:getAttrs(oid, iid, rid), self.reporters[oid]

    resrcReporter = resrcReporter and resrcReporter[iid]
    resrcReporter = resrcReporter and resrcReporter[rid]

    if (resrcReporter == nil) then return self end
    if (resrcAttrs == nil) then resrcAttrs = self:_findAttrs(oid, iid, rid) end
    -- if resrcAttrs was set before, dont delete it.
    resrcAttrs.cancel = true
    resrcAttrs.mute = true

    if (resrcReporter) then
        timer.clearTimeout(resrcReporter.minRep)
        timer.clearInterval(resrcReporter.maxRep)
        timer.clearInterval(resrcReporter.poller)
        resrcReporter.minRep = nil
        resrcReporter.maxRep = nil
        resrcReporter.poller = nil
    end
    return self
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