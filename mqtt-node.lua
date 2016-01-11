------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENSE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
local EventEmitter = require 'events'
local timer = require 'timer'

local tmoutms = 60000
local errcode = { success = 0, notfound = 1, unreadable = 2, unwritable = 3, timeout = 4, nilclient = 5 }
local cmdcode = { read = 0, write = 1, discover = 2, writeAttrs = 3, execute = 4, observe = 5, notify = 6 , unknown = 255 }
local trgtype = { root = 0, object = 1, instance = 2, resource = 3 }
local rspcode = { ok = 200, created = 201, deleted = 202, changed = 204, content = 205,
                  badreq = 400, unauth = 401, notfound = 404, notallow = 405, conflict = 409 }
local tag = { notfound = '_notfound_', unreadable = '_unreadable_', exec = '_exec_', unwritable = '_unwritable_' }

local MqttNode = EventEmitter({ clientId = nil, lifetime = 86400, version = '0.0.1' })

local modName = ...
_G[modName] = MqttNode

function MqttNode:new(qnode)
    qnode = qnode or {}
    assert(type(qnode.mac) == 'string', "mac address should be given with a string.")   -- qnode.mac and qnode.ip are MUSTs
    assert(type(qnode.ip) == 'string', "ip address should be given with a string.")
    if (qnode.clientId == nil) then qnode.clientId = 'qnode-' .. qnode.mac end

    qnode.lifetime = qnode.lifetime or self.lifetime
    qnode.version = qnode.version or self.version
    qnode.mc = nil
    qnode.so = nil

    qnode._trandId = 0
    qnode._repAttrs = {}
    qnode._tobjs = {}
    qnode._lfCountSecs = 0
    qnode._lfUpdater = nil

    qnode._pubics = {
        register = 'register/' .. node.clientId,
        deregister = 'deregister/' .. node.clientId,
        notify = 'notify/' .. node.clientId,
        update = 'update/' .. node.clientId,
        ping = 'ping/' .. node.clientId,
        response = 'response/' .. node.clientId
    }

    qnode._subics = {
        register = 'register/response/' .. node.clientId,
        deregister = 'deregister/response/' .. node.clientId,
        notify = 'notify/response/' .. node.clientId,
        update = 'update/response/' .. node.clientId,
        ping = 'ping/response/' .. node.clientId,
        request = 'request/' .. node.clientId,
        announce = 'announce'
    }

    self:_buildDefaultSo(qnode)  -- Build Default Objects
    self.__index = self
    qnode = setmetatable(qnode, self)
    return qnode
end

function MqttNode:encrypt(msg) return msg end
function MqttNode:decrypt(msg) return msg end

function MqttNode:setDevAttrs(devAttrs)
    local updated = {}

    for k, v in pairs(devAttrs) do  -- only these 3 parameters can be changed at runtime
        if (k == 'lifetime' or k == 'ip' or k == 'version') then
            if (self[k] ~= v) then
                self[k] = v
                updated[k] = v
            end
        end
    end

    if (next(updated) ~= nil) then
        self.so[1][1] = self.lifetime
        self.so[4][4] = self.ip
        self:pubUpdate(updated)
    end
end

function MqttNode:initResrc(...)
    local oid, iid, resrcs = ...

    oid = tonumber(oid) or oid
    iid = tonumber(iid) or iid
    self.so[oid] = self.so[oid] or {}
    self.so[oid][iid] = self.so[oid][iid] or {}

    for rid, rval in pairs(resrcs) do
        if (type(rval) ~= 'function') then
            self.so[oid][iid][rid] = rval
            if (type(rval) == 'table') then
                rval._isCb = type(rval.read) == 'function' or type(rval.write) == 'function' or type(rval.exec) == 'function'
            end
        end
    end
    return self
end

function MqttNode:readResrc(oid, iid, rid, callback)
    return self:_readResrc(true, oid, iid, rid, callback)
end

function MqttNode:writeResrc(oid, iid, rid, value, callback)
    local result
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid
    callback = callback or function(...) end

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, nil)
    else
        local resrc = self.so[oid][iid][rid]
        local rtype = type(resrc)
        if (rtype == 'table') then
            if (resrc._isCb) then
                if (type(resrc.write) == 'function') then
                    pcall(resrc.write, value, function (err, val)
                        result = val
                        callback(err, val)
                    end)
                else callback(errcode.unwritable, nil) end
            else
                self.so[oid][iid][rid] = value
                result = value
                callback(errcode.success, value)
            end
        elseif (rtype == 'function' or rtype == 'thread') then
            callback(errcode.unwritable, nil)
        else
            self.so[oid][iid][rid] = value
            result = value
            callback(errcode.success, value)
        end
    end
    if (result ~= nil) then self:_checkAndReportResrc(oid, iid, rid, result) end
end

function MqttNode:execResrc(oid, iid, rid, args, callback)
    callback = callback or function(...) end
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, { status = rspcode.notfound })
    else
        local resrc = self.so[oid][iid][rid]

        if (type(resrc) ~= 'table' or type(resrc.exec) ~= 'function') then
            callback(errcode.notallow, { status = rspcode.notallow })
        else
            pcall(resrc.exec, args, callback) -- unpack by their own, resrc.exec(args, callback)
        end
    end
end

function MqttNode:dump()
    local dump = {
        clientId = self.clientId, lifetime = self.lifetime, ip = self.ip, mac = self.mac,
        version = self.version, so = {}
    }
    for oid, obj in pairs(self.so) do dump.so[oid] = self:_dumpObject(oid) end
    return dump
end

function MqttNode:objectList()
    local objList = {}
    for oid, obj in pairs(self.so) do
        for iid, _ in pairs(obj) do table.insert(objList, { oid = oid, iid = iid }) end
    end
    return objList
end

function MqttNode:resrcList(oid)
    local obj, resrcList = self.so[oid], {}
    for iid, resrcs in pairs(obj) do
        resrcList[iid] = {}
        for rid, r in resrcs do table.insert(resrcList[iid], rid) end
    end
    return resrcList
end

function MqttNode:_requestHandler(msg)
    local rsp = { transId = msg.transId, cmdId = msg.cmdId, status = rspcode.ok, data = nil }
    local tgtype, target = self:_target(msg.oid, msg.iid, msg.rid)

    if (tgtype == trgtype.root or msg.oid == nil) then
        rsp.status = rspcode.badreq -- Request Root is not allowed
        self:pubResponse(rsp)
        return
    end

    if (target == tag.notfound) then
        rsp.status = rspcode.notfound
        self:pubResponse(rsp)
        return
    end

    if (msg.cmdId == cmdcode.read) then
        if (target == tag.unreadable) then rsp.status = rspcode.notallow
        else rsp.status = rspcode.content
        end
        rsp.data = target
    elseif (msg.cmdId == cmdcode.write) then
        -- [TODO] 1. allow object and instance 2. tackle access control in the near future
        if (tgtype == trgtype.object or tgtype == trgtype.instance) then    -- will support in the future
            rsp.status = rspcode.notallow
        elseif (tgtype == trgtype.resource) then
            self:writeResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, val)
                if (err == errcode.unwritable) then
                    rsp.status = rspcode.notallow
                else
                    rsp.status = rspcode.changed
                    rsp.data = val
                end
            end)
        end
    elseif (cmdId == cmdcode.discover) then
        local export, attrs = {}
        if (tgtype == trgtype.object) then
            attrs = self:getAttrs(msg.oid) or {}
            attrs.resrcList = self:resrcList(msg.oid)
        elseif (tgtype == trgtype.instance) then attrs = self:getAttrs(msg.oid, msg.iid)
        elseif (tgtype == trgtype.resource) then attrs = self:getAttrs(msg.oid, msg.iid, msg.rid)
        end
        for k, v in pairs(attrs) do if (k ~= 'mute' and k ~= 'lastrp') then export[k] = v end end
        rsp.status = rspcode.content
        rsp.data = export
    elseif (cmdId == cmdcode.writeAttrs) then
        local badAttr = false
        local allowedAttrsMock = { pmin = true, pmax = true, gt = true, lt = true, step = true, cancel = true, pintvl = true }

        if (msg.attrs ~= 'table') then
            rsp.status = rspcode.badreq
        else
            for k, v in pairs(msg.attrs) do if (allowedAttrsMock[k] ~= true) then badAttr = true end end
            if (badAttr == true) then
                rsp.status = rspcode.badreq
            else
                rsp.status = rspcode.changed
                if (tgtype == trgtype.object) then
                    if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end   -- [TODO] always avoid report, support in future
                    self:setAttrs(msg.oid, msg.attrs)
                elseif (tgtype == trgtype.instance) then
                    if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end   -- [TODO] always avoid report, support in future
                    self:setAttrs(msg.oid, msg.iid, msg.attrs)
                elseif (tgtype == trgtype.resource) then
                    if (msg.attrs.cancel) then self:disableReport(msg.oid, msg.iid, msg.rid) end
                     self:setAttrs(msg.oid, msg.iid, msg.rid, msg.attrs)
                else
                    rsp.status = rspcode.notfound
                end
            end
        end
    elseif (cmdId == cmdcode.execute) then
        if (tgtype ~= trgtype.resource) then
            rsp.status = rspcode.notallow
        else
            rsp.status = rspcode.changed
            self:execResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, execRsp)
                for k, v in pairs(execRsp) do rsp[k] = v end
            end)
        end
    elseif (cmdId == cmdcode.observe) then
        rsp.status = rspcode.changed
        if (tgtype == trgtype.object or tgtype == trgtype.instance) then
             rsp.status = rspcode.notallow   -- [TODO] will support in the future
        elseif (tgtype == trgtype.resource) then
            self:enableReport(msg.oid, msg.iid, msg.rid)
        end
    elseif (cmdId == cmdcode.notify) then
        return  -- notify, this is not a request, do nothing
    else
        rsp.status = rspcode.badreq -- unknown request
    end

    self:pubResponse(rsp)
end

function MqttNode:_rawMessageHandler(conn, topic, message)
    local strmsg, intf = self:decrypt(message), mutils.slashPath(topic)
    local rspCb, jmsg, tid, _evt

    self:emit('message', topic, strmsg)    -- emit raw message out

    if (strmsg:sub(1, 1) == '{' and strmsg:sub(-1) == '}') then
        jmsg = cjson.decode(strmsg) -- decode to json msg
        tid = tostring(jmsg.transId)
    end

    if (intf == self._subics.register) then
        if (jmsg.status == 200 or jmsg.status == 201) then self:_lifeUpdate(true)
        else self:_lifeUpdate(false)
        end
        _evt = 'register:rsp:' .. tid
    elseif (intf == self._subics.deregister) then
        _evt = 'deregister:rsp:' .. tid
    elseif (intf == self._subics.notify) then
        _evt = 'notify:rsp:' .. tid
    elseif (intf == self._subics.update) then
        _evt = 'update:rsp:' .. tid
    elseif (intf == self._subics.ping) then
        _evt = 'ping:rsp:' .. tid
    elseif (intf == self._subics.request) then      -- No callbacks
        self:_requestHandler(jmsg)
    elseif (intf == self._subics.announce) then     -- No callbacks
        self:emit('announce', strmsg)
    end

    if (_evt ~= nil) then
        self:emit(_evt, jmsg)
        if (self._tobjs[key] ~= nil) then timer.clearTimeout(self._tobjs[key]) end
    end
end

function MqttNode:connect(url, opts)
    assert(_G['mqtt'] ~= nil, "mqtt module is not loaded.")
    opts = opts or {}
    opts.username = opts.username or 'freebird'
    opts.password = opts.password or 'skynyrd'
    opts.keepalive = opts.keepalive or 120
    opts.port = opts.port or 1883
    opts.secure = opts.secure or 0
    opts.cleansession = opts.cleansession or 1

    if (self.mc == nil) then self.mc = mqtt.Client(self.clientId, opts.keepalive, opts.username, opts.password, opts.cleansession) end

    local mc = self.mc
    mc:connect(url, opts.port, opts.secure, function (c)
        mc:on('message', function (client, topic, msg) self:_rawMessageHandler(client, topic, msg) end)
    end)
end

function MqttNode:close(callback)
    if (self.mc ~= nil) then self.mc:close() end
    if (callback ~= nil) then callback() end
end

function MqttNode:pubRegister(callback)
    local transId = self:_nextTransId('register')
    local regData = { transId = transId, lifetime = self.lifetime, objList = self:objectList(),
                      ip = self.ip, mac = self.mac, version = self.version }
    if (callback ~= nil and self.mc ~= nil) then
        local key = 'register:rsp:' .. tostring(transId)
        self:once(key, callback)
        self:_timeoutCtrl(key, tmoutms)
    end
    return self:publish(self._pubics.register, regData)
end

function MqttNode:pubDeregister(callback)
    local transId = self:_nextTransId('deregister')
    if (callback ~= nil and self.mc ~= nil) then
        local key = 'deregister:rsp:' .. tostring(transId)
        self:once(key, callback)
        self:_timeoutCtrl(key, tmoutms)
    end
    return self:publish(self._pubics.deregister, { transId = transId, data = nil })
end

function MqttNode:pubNotify(data, callback)
    data.transId = self:_nextTransId('notify')

    if (self.mc ~= nil) then
        local key = 'notify:rsp:' .. tostring(data.transId)
        self:once(key, function (err, rsp)
            if (rsp.cancel) then self:disableReport(data.oid, data.iid, data.rid) end
            if (callback ~= nil) then callback(err, rsp) end
        end)
        self:_timeoutCtrl(key, tmoutms)
    end
    return self:publish(self._pubics.notify, data)
end

function MqttNode:pingServer(callback)
    local transId = self:_nextTransId('ping')
    if (callback ~= nil and self.mc ~= nil) then
        local key = 'ping:rsp:' .. tostring(transId)
        self:once(key , callback)
        self:_timeoutCtrl(key, tmoutms)
    end
    return self:publish(self._pubics.ping, { transId = transId, data = nil })
end

function MqttNode:pubUpdate(devAttrs, callback)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    devAttrs.transId = self:_nextTransId('update')
    if (callback ~= nil and self.mc ~= nil) then
        local key = 'update:rsp:' .. tostring(devAttrs.transId)
        self:once(key, callback)
        self:_timeoutCtrl(key, tmoutms)
    end
    return self:publish(self._pubics.update, devAttrs)
end

function MqttNode:pubResponse(rsp, callback)
    return self:publish(self._pubics.response, rsp, callback)
end

function MqttNode:publish(topic, message, options, callback)
    assert(self.mc ~= nil, "mqtt client is nil, cannot publish")
    if (type(options) == 'function') then
        callback = options
        options = nil
    end
    local qos, retain, jmsg = options.qos or 0, options.retain or 0, message

    if (type(message) == 'table') then message = cjson.encode(message) end
    local encrypted = self:encrypt(message)

    self.mc:publish(topic, encrypted, qos, retain, function (client)
        self:emit('published', { topic = topic, message = jmsg, options = options })
        if (callback ~= nil) then callback() end
    end)
end

function MqttNode:subscribe(topic, qos, callback)
    if (type(qos) == 'function') then
        callback = qos
        qos = nil
    end
    local q = qos or 0
    if (self.mc ~= nil) then self.mc:subscribe(topic, q, callback) end
end

function MqttNode:getAttrs(...)
    local oid, iid, rid = ...
    local tgtype, target, key, attrs = self:_target(...), tostring(oid)
    local default = { pmin = self.so[1][2], pmax = self.so[1][3], mute = true, cancel = true }

    if (target == tag.notfound) then return nil end
    if (tgtype == trgtype.object) then key = key
    elseif (tgtype == trgtype.instance) then key = key .. ':' .. tostring(iid)
    elseif (tgtype == trgtype.resource) then key = key .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    end
    self._repAttrs[key] = self._repAttrs[key] or default

    return self._repAttrs[key]
end

function MqttNode:setAttrs(...) -- args: oid, iid, rid, attrs
    local argtbl = { ... }
    local oid, key = argtbl[1], tostring(argtbl[1])
    local iid, rid, tgtype, target, attrs

    if (#argtbl == 4) then
        iid, rid, attrs = argtbl[2], argtbl[3], argtbl[4]
        key = key .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    elseif (#argtbl == 3) then
        iid, attrs = argtbl[2], argtbl[3]
        key = key .. ':' .. tostring(iid)
    elseif (#argtbl == 2) then
        attrs = argtbl[2]
    end

    tgtype, target = self:_target(oid, iid, rid)
    if (target == tag.notfound) then return false end
    attrs.pmin = attrs.pmin or self.so[1][2]
    attrs.pmax = attrs.pmax or self.so[1][3]
    self._repAttrs[key] = attrs
    return true
end

-- ********************************************* --
-- **  Protected Methods                      ** --
-- ********************************************* --
function MqttNode:_target(oid, iid, rid)
    local tgtype, target

    if (oid ~= nil and oid == '') then tgtype = trgtype.root
    elseif (oid ~= nil) then tgtype = trgtype.object
        if (iid ~= nil) then tgtype = trgtype.instance
            if (rid ~= nil) then tgtype = trgtype.resource end
        end
    end

    if (tgtype == trgtype.object) then target = self:_dumpObject(oid)
    elseif (tgtype == trgtype.instance) then target = self:_dumpObject(oid, iid) 
    elseif (tgtype == trgtype.resource) then self:_readResrc(false, oid, iid, rid, function (err, val) target = val end)
    end

    if (target == nil) then target = tag.notfound end
    return tgtype, target
end

function MqttNode:_nextTransId(intf)
    local nextid = function ()
        self._trandId = self._trandId + 1
        if (self._trandId > 255) then self._trandId = 0 end
    end

    if (intf ~= nil) then
        local rspid = intf .. ':rsp:' .. tostring(self._trandId)
        while self:listenerCount(rspid) ~= 0 do rspid = intf .. ':rsp:' .. tostring(nextid()) end
    end
    return self._trandId
end

function MqttNode:_dumpObject(...)
    local oid, iid = ...
    local dump, obj = {}, self.so[oid]

    if (obj == nil) then return nil end

    if (iid == nil) then        -- dump object
        for ii, inst in pairs(obj) do
            dump[ii] = {}
            for rid, resrc in pairs(obj[ii]) do
                self:readResrc(oid, ii, rid, function (err, val) dump[ii][rid] = val end)
            end
        end
    else                       -- dump instance
        if (obj[iid] == nil) then return nil end
        for rid, resrc in pairs(obj[iid]) do
            self:readResrc(oid, iid, rid, function (err, val) dump[rid] = val end)
        end
    end

    return dump
end

function MqttNode:_buildDefaultSo(qnode)
    qnode.so = qnode.so or {}

    -- Add Default Objects
    -- LWM2M Object: LWM2M Server Object
    qnode.so[1] = {
        -- 0 = short server id, 1 = lifetime, 2 = default pmin, 3 = default pmax, 8 = registration update trigger
        [0] = nil, [1] = self.lifetime, [2] = 1, [3] = 60, [8] = { exec = function (...) end }
    }
    -- LWM2M Object: Device
    qnode.so[3] = {
        -- 0 = manuf, 1 = model, 4 = reboot, 5 = factory reset, 6 = available power sources,
        -- 7 = power source voltage, 17 = device type, 18 = hardware version, 19 = software version
        [0] = 'freebird', [1] = 'mqtt-node', 
        [4] = { exec = function () node.restart() end },
        [5] = { exec = function ()
                -- [TODO]
                end },
        [6] = 0, [7] = 5000, [17] = 'generic', [18] = 'v0.0.1', [19] = 'v0.0.1',
    }
    -- LWM2M Object: Connectivity Monitoring
    qnode.so[4] = {
        -- 4 = ip, 5 = router ip
        [4] = self.ip, [5] = nil
    }
end

function MqttNode:_lifeUpdate(enable)
    self._lfCountSecs = 0

    if (self._lfUpdater ~= nil) then
        timer.clearInterval(self._lfUpdater)
        self._lfUpdater = nil
    end

    if (enable == true) then
        self._lfUpdater = timer.setInterval(function ()
            self._lfCountSecs = self._lfCountSecs + 1
            if (self._lfCountSecs == self.lifetime) then
                self:pubUpdate({ lifetime = self.lifetime })
                self._lfCountSecs = 0
            end
        end, 1000)
    end
end

function MqttNode:_checkAndReportResrc(oid, iid, rid, currVal)
    local attrs, rpt = self:getAttrs(oid, iid, rid), false

    if (attrs == nil) then return false end    -- target not found
    if (attrs.cancel or attrs.mute) then return false end

    local lastrp, gt, lt, step = attrs.lastrp, attrs.gt, attrs.lt, attrs.step

    if (type(currVal) == 'table') then
        if (type(lastrp) == 'table') then for k, v in pairs(currVal) do rpt = rpt or v ~= lastrp[k] end
        else rpt = true
        end
    elseif (type(currVal) ~= 'number') then
        rpt = lastrp ~= currVal
    else
        if (type(gt) == 'number' and type(lt) == 'number' and lt > gt) then
            rpt = lastrp ~= currVal and currVal > gt and currVal < lt
        else
            rpt = type(gt) == 'number' and lastrp ~= currVal and currVal > gt
            rpt = rpt or type(lt) == 'number' and lastrp ~= currVal and currVal < lt
        end

        if (type(step) == 'number') then rpt = rpt or math.abs(currVal - lastrp) > step end
    end

    if (rpt) then
        attrs.lastrp = currVal
        self:pubNotify({ oid = oid, iid = iid, rid = rid, data = currVal })
    end

    return rpt
end

function MqttNode:enableReport(oid, iid, rid, attrs)
    local tgtype, target = self:_target(oid, iid, rid)
    if (target == tag.notfound) then return false end

    local resrcAttrs = self:getAttrs(oid, iid, rid)
    local rpid = tostring(oid) .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    local pminMs, pmaxMs, rRpt = resrcAttrs.pmin * 1000, resrcAttrs.pmax * 1000 -- pmin and pmax are MUSTs

    resrcAttrs.cancel = false
    resrcAttrs.mute = true

    self.reporters[rpid] = { minRep = nil, maxRep = nil, poller = nil } -- reporter place holder
    rRpt = self.reporters[rpid]

    rRpt.minRep = timer.setTimeout(function ()  -- mute is use to control the poller
        if (pminMs == 0) then resrcAttrs.mute = false   -- if no pmin, just report at pmax triggered
        else self:readResrc(oid, iid, rid, function (err, val)
                resrcAttrs.mute = false
                self:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
            end)
        end
    end, pminMs)

    rRpt.maxRep = timer.setInterval(function ()
        resrcAttrs.mute = true
        self:readResrc(oid, iid, rid, function (err, val)
            resrcAttrs.mute = false
            self:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
        end)

        if (rRpt.minRep ~= nil) then timer.clearTimeout(rRpt.minRep) end
        rRpt.minRep = nil
        rRpt.minRep = timer.setTimeout(function ()
            if (pminMs == 0) then resrcAttrs.mute = false   --  if no pmin, just report at pmax triggered
            else self:readResrc(oid, iid, rid, function (err, val)
                    resrcAttrs.mute = false
                    self:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
                end)
            end
        end, pminMs)
    end, pmaxMs)

    return true
end

function MqttNode:disableReport(oid, iid, rid)
    local rpid = tostring(oid) .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    local resrcAttrs, rRpt = self:getAttrs(oid, iid, rid), self.reporters[rpid]

    if (rRpt == nil) then return false end
    if (resrcAttrs == nil) then return false end

    resrcAttrs.cancel = true
    resrcAttrs.mute = true

    timer.clearTimeout(rRpt.minRep)
    timer.clearInterval(rRpt.maxRep)
    timer.clearInterval(rRpt.poller)
    rRpt.minRep = nil
    rRpt.maxRep = nil
    rRpt.poller = nil
    self.reporters[rpid] = nil
    return true
end

function MqttNode:_readResrc(chk, oid, iid, rid, callback)
    local result
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid
    callback = callback or function(...) end

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, nil)
    else
        local resrc = self.so[oid][iid][rid]
        local rtype = type(resrc)
        if (rtype == 'table' and resrc._isCb == true) then
            if (type(resrc.read) == 'function') then
                pcall(resrc.read, function (err, val)
                    result = val
                    callback(err, val)
                end)
            elseif (type(resrc.exec) == 'function') then callback(errcode.unreadable, tag.exec)
            else callback(errcode.unreadable, tag.unreadable)
            end
        elseif (rtype == 'function' or rtype == 'thread') then
            callback(errcode.unreadable, nil)
        else
            result = resrc
            callback(errcode.success, resrc)
        end
    end

    if (chk == true and result ~= nil) then self:_checkAndReportResrc(oid, iid, rid, result) end
end

function MqttNode:_timeoutCtrl(key, delay)
    self._tobjs[key] = timer.setTimeout(function ()
        self:emit(key, { status = errcode.timeout })
        if (self._tobjs[key] ~= nil) then self._tobjs[key] = nil end
    end, delay)
end

return MqttNode

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