------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENSE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
local EventEmitter = require 'events'
local timer = require 'timer'

-- ************** Code Enumerations **************
local errcode = { success = 0, notfound = 1, unreadable = 2, unwritable = 3, timeout = 4 }
local cmdcode = { read = 0, write = 1, discover = 2, writeAttrs = 3, execute = 4, observe = 5, notify = 6 , unknown = 255 }
local trgtype = { root = 0, object = 1, instance = 2, resource = 3 }
local rspcode = { ok = 200, created = 201, deleted = 202, changed = 204, content = 205,
                  badreq = 400, unauth = 401, notfound = 404, notallow = 405, conflict = 409 }

local MqttNode = EventEmitter({ clientId = nil, lifetime = 86400, ip = nil, mac = nil, version = '0.0.1' })

local modName = ...
_G[modName] = MqttNode

function MqttNode:new(qnode)
    qnode = qnode or {}


    -- qnode.mac and qnode.ip are MUSTs
    assert(type(qnode.mac) == 'string', "mac address should be given with a string.")
    assert(type(qnode.ip) == 'string', "ip address should be given with a string.")

    if (qnode.clientId == nil) then qnode.clientId = 'qnode-' .. qnode.mac end

    qnode.lifetime = qnode.lifetime or self.lifetime
    qnode.version = qnode.version or self.version
    qnode.mc = nil
    qnode.so = nil

    qnode._repAttrs = {}
    qnode._trandId = 0
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

function MqttNode:setDevAttrs(devAttrs)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    local updated, pub = {}, false

    for k, v in pairs(devAttrs) do  -- only these 3 parameters can be changed at runtime
        if (k == 'lifetime' or k == 'ip' or k == 'version') then
            if (self[k] ~= v) then
                self[k] = v
                updated[k] = v
                pub = true
            end
        end
    end

    if (pub == true) then self:pubUpdate(updated) end
end

-- iid should be given
function MqttNode:initResrc(...)
    local oid, iid, resrcs = ...
    assert(type(resrcs) == "table", "resrcs should be a table.")

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
    local result
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
            elseif (type(resrc.exec) == 'function') then callback(errcode.unreadable, '_exec_')
            else callback(errcode.unreadable, '_unreadable_') end
        elseif (rtype == 'function' or rtype == 'thread') then
            callback(errcode.unreadable, nil)
        else
            result = resrc
            callback(errcode.success, resrc)
        end
    end

    if (result ~= nil) then self:_checkAndReportResrc(oid, iid, rid, result) end
end

function MqttNode:writeResrc(oid, iid, rid, value, callback)
    local result
    callback = callback or function(...) end

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, nil)
    else
        local resrc = self.so[oid][iid][rid]
        if (type(resrc) == 'table') then
            if (resrc._isCb) then
                if (type(resrc.write) == 'function') then
                    pcall(resrc.write, value, function (err, val)
                        result = val
                        callback(err, val)
                    end)
                else callback(errcode.unwritable, nil) end
            else
                resrc = value
                result = resrc
                callback(errcode.success, resrc)
            end
        elseif (type(resrc) == 'function' or type(resrc) == 'thread') then
            callback(errcode.unwritable, nil)
        else
            resrc = value
            result = resrc
            callback(errcode.success, resrc)
        end
    end
    if (result ~= nil) then self:_checkAndReportResrc(oid, iid, rid, result) end
end

function MqttNode:execResrc(oid, iid, rid, args, callback)
    callback = callback or function(...) end

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(errcode.notfound, { status = rspcode.notfound })
    else
        local resrc = self.so[oid][iid][rid]

        if (type(resrc) ~= 'table' or type(resrc.exec) ~= 'function') then
            callback(errcode.notfound, { status = rspcode.notallow })
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
        for iid, inst in pairs(obj) do table.insert(objList, { oid = oid, iid = iid }) end
    end
    return objList
end

function MqttNode:encrypt(msg)
    return msg
end

function MqttNode:decrypt(msg)
    return msg
end

function MqttNode:resrcList(oid)
    local obj, resrcList = self.so[oid], {}
    if (type(obj) == 'table') then
        for iid, resrcs in pairs(obj) do
            resrcList[iid] = {}
            for rid, r in resrcs do table.insert(resrcList[iid], rid) end
        end
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

    if (target == '__notfound') then
        rsp.status = rspcode.notfound
        self:pubResponse(rsp)
        return
    end

    if (msg.cmdId == cmdcode.read) then
        if (target == '_unreadable_') then rsp.status = rspcode.notallow
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
        local attrs
        if (tgtype == trgtype.object) then
            attrs = self:getAttrs(msg.oid)
            attrs = attrs or {}
            attrs.resrcList = self:resrcList(msg.oid)
        elseif (tgtype == trgtype.instance) then attrs = self:getAttrs(msg.oid, msg.iid)
        elseif (tgtype == trgtype.resource) then attrs = self:getAttrs(msg.oid, msg.iid, msg.rid)
        end
        rsp.status = rspcode.content
        rsp.data = attrs
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
                    if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end   -- always avoid report, support in future
                    -- [TODO] should be partially set?
                    self:setAttrs(msg.oid, msg.attrs)
                elseif (tgtype == trgtype.instance) then
                    if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end   -- always avoid report, support in future
                    -- [TODO] should be partially set?
                    self:setAttrs(msg.oid, msg.iid, msg.attrs)
                elseif (tgtype == trgtype.resource) then
                    if (msg.attrs.cancel) then self:disableReport(msg.oid, msg.iid, msg.rid) end
                    -- [TODO] should be partially set?
                    self:setAttrs(msg.oid, msg.iid, msg.rid, msg.attrs)
                else
                    rsp.status = rspcode.notfound
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
    local rspCb, jmsg, tid

    self:emit('message', strmsg)    -- emit raw message out

    if (strmsg:sub(1, 1) == '{' and strmsg:sub(-1) == '}') then
        jmsg = cjson.decode(strmsg) -- decode to json msg
        tid = tostring(jmsg.transId)
    end

    if (intf == self._subics.register) then
        if (jmsg.status == 200 or jmsg.status == 201) then self:_lfUpdater(true)
        else self:_lfUpdater(false)
        end
        self:emit('register:' .. tid, jmsg)
    elseif (intf == self._subics.deregister) then
        self:emit('deregister:' .. tid, jmsg)
    elseif (intf == self._subics.notify) then
        self:emit('notify:' .. tid, jmsg)
    elseif (intf == self._subics.update) then
        self:emit('update:' .. tid, jmsg)
    elseif (intf == self._subics.ping) then
        self:emit('ping:' .. tid, jmsg)
    elseif (intf == self._subics.request) then      -- No callback
        evt = 'request'
        self:_requestHandler(jmsg)
    elseif (intf == self._subics.announce) then     -- No callback
        evt = 'announce'
        jmsg = strmsg
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
    local regPubChannel, transId = self._pubics.register, self:_nextTransId('register')
    local tid = tostring(regData.transId)
    local regData = {
            transId = transId,
            lifetime = self.lifetime,
            objList = self:objectList(),
            ip = self.ip,
            mac = self.mac,
            version = self.version,
         }

    if (callback ~= nil) then self:once('register:' .. tid, callback) end
    self:publish(regPubChannel, regData)
end

function MqttNode:pubDeregister(callback)
    local deregPubChannel, transId = self._pubics.deregister, self:_nextTransId('deregister')
    local tid = tostring(transId)
    if (callback ~= nil) then self:once('deregister:' .. tid, callback) end
    self:publish(deregPubChannel, { transId = transId, data = nil })
end

function MqttNode:pubNotify(data, callback)
    local notifyPubChannel, transId = self._pubics.notify, self:_nextTransId('notify')
    local tid = tostring(transId)
    data.transId = transId

    self:once('notify:' .. tid, function (err, rsp)
        if (rsp.cancel) then self:disableReport(data.oid, data.iid, data.rid) end
        if (callback ~= nil) then callback(err, rsp) end
    end)

    self:publish(notifyPubChannel, data)
end

function MqttNode:pingServer(callback)
    local pingPubChannel, transId = self._pubics.ping, self:_nextTransId('ping')
    local tid = tostring(transId)
    if (callback ~= nil) then self:once('ping:' .. tid, callback) end
    self:publish(pingPubChannel, { transId = transId, data = nil })
end

function MqttNode:pubUpdate(devAttrs, callback)
    assert(type(devAttrs) == "table", "devAttrs should be a table.")
    assert(devAttrs.mac == nil, "mac cannot be changed at runtime.")

    local updatePubChannel, transId = self._pubics.update, self:_nextTransId('update')

    devAttrs.transId = transId
    if (callback ~= nil) then self:once('update:' .. tid, callback) end
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
    elseif (tgtype == trgtype.instance) then target = self:_dumpObject(oid, iid) 
    elseif (tgtype == trgtype.resource) then self:readResrc(oid, iid, rid, function (err, val) target = val end)
    end

    if (target == nil) then target = '__notfound' end

    return tgtype, target
end

function MqttNode:_nextTransId(intf)
    self._trandId = self._trandId + 1
    if (self._trandId > 255) then self._trandId = 0 end

    if (intf ~= nil) then
        local rspid = intf .. tostring(self._trandId)
        while self:listenerCount(rspid) ~= 0 do 
            self._trandId = self._trandId + 1
            if (self._trandId > 255) then self._trandId = 0 end
            rspid = intf .. tostring(self._trandId)
        end
    end
    return self._trandId
end

function MqttNode:_dumpObject(...)
    local oid, iid = ...
    local dump, obj = {}, self.so[oid]

    if (obj == nil) then return nil end

    if (iid == nil) then        -- dump object
        dump[iid] = {}
        for ii, inst in pairs(obj) do
            for rid, resrc in pairs(obj[ii]) do
                self:readResrc(oid, ii, rid, function (err, val) dump[iid][rid] = val end)
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

function MqttNode:_startLifeUpdater(enable)
    self._lfCountSecs = 0

    if (self._lfUpdater ~= nil) then
        timer.clearInterval(self._lfUpdater)
        self._lfUpdater = nil
    end

    if (enable == true) then
        self.lifeUpdater = timer.setInterval(function ()
            self._lfCountSecs = self._lfCountSecs + 1
            if (self._lfCountSecs == self.lifetime) then
                self:pubUpdate({ lifetime = self.lifetime })
                self:_lfUpdater(true)
            end
        end, 1000)
    end
end

-- [TODO] who use this method?
function MqttNode:_checkAndReportResrc(oid, iid, rid, currVal)
    local attrs, rpt = self:getAttrs(oid, iid, rid), false

    if (attrs == nil) then return false end    -- no attrs were set
    if (attrs.cancel or attrs.mute) then return false end

    local lastrp, gt, lt, step = attrs.lastrp, attrs.gt, attrs.lt, attrs.step

    if (type(currVal) == 'table') then
        if (type(lastrp) == 'table') then
            for k, v in pairs(currVal) do
                if (v ~= lastrp[k]) then rpt = true end
            end
        else
            rpt = true
        end

    elseif (type(currVal) ~= 'number') then
        if (lastrp ~= currVal) then rpt = true end
    else
        if (type(gt) == 'number' and type(lt) == 'number' and lt > gt) then
            if (lastrp ~= currVal and currVal > gt and currVal < lt) then rpt = true end
        else
            if (type(gt) == 'number' and lastrp ~= currVal and currVal > gt) then rpt = true end
            if (type(lt) == 'number' and lastrp ~= currVal and currVal < lt) then rpt = true end
        end

        if (type(step) == 'number') then
            if (math.abs(currVal - lastrp) > step) then rpt = true end
        end
    end

    if (rpt) then
        attrs.lastrp = currVal
        self:pubNotify({ oid = oid, iid = iid, rid = rid, data = currVal })
    end

    return rpt
end

-- [TODO] need check
function MqttNode:enableReport(oid, iid, rid, attrs)
    local tgtype, target = self:_target(oid, iid, rid)
    if (target == '__notfound') then return false end

    local resrcAttrs = self:getAttrs(oid, iid, rid)
    local rpid = tostring(oid) .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    local rRpt, pminMs, pmaxMs

    if (resrcAttrs == nil) then resrcAttrs = self:_findAttrs(oid, iid, rid) end

    resrcAttrs.cancel = false
    resrcAttrs.mute = true

    -- [TODO] pmin and pmax are MUSTs
    pminMs = resrcAttrs.pmin * 1000 or 0
    pmaxMs = resrcAttrs.pmax * 1000 or 600000

    -- reporter place holder
    self.reporters[rpid] = { minRep = nil, maxRep = nil, poller = nil }
    rRpt = self.reporters[rpid]

    -- mute is use to control the poller
    rRpt.minRep = timer.setTimeout(function ()
        if (pminMs == 0) then   -- if no pmin, just report at pmax triggered
            resrcAttrs.mute = false
        else
            self:readResrc(oid, iid, rid, function (err, val)
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

        rRpt.minRep = nil
        rRpt.minRep = timer.setTimeout(function ()
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
    local rpid = tostring(oid) .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    local resrcAttrs, rRpt = self:getAttrs(oid, iid, rid), self.reporters[rpid]

    if (rRpt == nil) then return self end
    if (resrcAttrs == nil) then resrcAttrs = self:_findAttrs(oid, iid, rid) end
    -- if resrcAttrs was set before, dont delete it.
    resrcAttrs.cancel = true
    resrcAttrs.mute = true

    if (rRpt) then
        timer.clearTimeout(rRpt.minRep)
        timer.clearInterval(rRpt.maxRep)
        timer.clearInterval(rRpt.poller)
        rRpt.minRep = nil
        rRpt.maxRep = nil
        rRpt.poller = nil
        self.reporters[rpid] = nil
        rRpt = nil
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