------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENSE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
local EventEmitter = require 'events'
local core = require 'mqcore'
local QNode = EventEmitter:new()
local _ms = 60000
function QNode:new(qn)
    qn = qn or {}
    assert(type(qn.mac) == 'string', "mac address should be given with a string.")
    assert(type(qn.ip) == 'string', "ip address should be given with a string.")
    qn.clientId = qn.clientId or 'qn-' .. qn.mac
    qn.lifetime = qn.lifetime or 86400
    qn.version = qn.version or '0.0.1'
    qn.mc = nil
    qn.so = nil

    qn._tid = 0
    qn._repAttrs = {}
    qn._tobjs = {}
    qn._lfCountSecs = 0
    qn._lfUpdater = nil

    self:_buildDefaultSo(qn)  -- Build Default Objects
    self.__index = self
    qn = setmetatable(qn, self)

    core.register(qn)
    return qn
end

function QNode:encrypt(msg) return msg end
function QNode:decrypt(msg) return msg end

function QNode:changeIp(ip)
    if (ip ~= self.ip) then
        self.ip = ip
        self.so[4][4] = self.ip
        self:pubUpdate({ ip = self.ip })
    end
end

function QNode:initResrc(...)
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

function QNode:readResrc(oid, iid, rid, callback)
    return self:_rd(true, oid, iid, rid, callback)
end

function QNode:writeResrc(oid, iid, rid, value, callback)
    local result
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid
    callback = callback or function(...) end

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(core.ERR.nfnd, nil)
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
                else callback(core.ERR.unwt, nil) end
            else
                self.so[oid][iid][rid] = value
                result = value
                callback(core.ERR.sces, value)
            end
        elseif (rtype == 'function' or rtype == 'thread') then
            callback(core.ERR.unwt, nil)
        else
            self.so[oid][iid][rid] = value
            result = value
            callback(core.ERR.sces, value)
        end
    end
    if (result ~= nil) then self:_chkResrc(oid, iid, rid, result) end
end

function QNode:execResrc(oid, iid, rid, args, callback)
    callback = callback or function(...) end
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(core.ERR.nfnd, { status = core.RSP.nfnd })
    else
        local resrc = self.so[oid][iid][rid]

        if (type(resrc) ~= 'table' or type(resrc.exec) ~= 'function') then
            callback(core.ERR.une, { status = core.RSP.nalw })
        else
            pcall(resrc.exec, args, callback) -- unpack by their own, resrc.exec(args, callback)
        end
    end
end

function QNode:connect(url, opts)
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
        mc:on('message', function (client, topic, msg) 
            self:emit('raw', client, topic, msg)
            -- self:_rawMessageHandler(client, topic, msg)
        end)
    end)
end

function QNode:close(callback)
    if (self.mc ~= nil) then self.mc:close() end
    if (callback ~= nil) then callback() end
end

function QNode:_pubReq(intf, data, callback)
    data.transId = self:_nextId(intf)
    if (callback ~= nil) then
        local key = intf .. ':rsp:' .. tostring(data.transId)
        core._timeoutCtrl(key, _ms)
        self:once(key, callback)
    end

    return self:publish(self._pubics[intf], data)
end

function QNode:pubRegister(callback)
    local regData = { transId = nil, lifetime = self.lifetime, objList = {},
                      ip = self.ip, mac = self.mac, version = self.version }

    for oid, obj in pairs(self.so) do
        for iid, _ in pairs(obj) do table.insert(regData.objList, { oid = oid, iid = iid }) end
    end

    return self:_pubReq('register', regData)
end

function QNode:pubDeregister(callback)
    return self:_pubReq('deregister', { data = nil })
end

function QNode:pubNotify(data, callback)
    return self:_pubReq('notify', data, function (err, rsp)
        if (rsp.cancel) then self:disableReport(data.oid, data.iid, data.rid) end
        if (callback ~= nil) then callback(err, rsp) end
    end)
end

function QNode:pingServer(callback)
    return self:_pubReq('ping', { data = nil })
end

function QNode:pubUpdate(devAttrs, callback)
    return self:_pubReq('update', devAttrs)
end

function QNode:pubResponse(rsp, callback)
    return self:publish(self._pubics.response, rsp, callback)
end

function QNode:publish(topic, message, options, callback)
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

function QNode:subscribe(topic, qos, callback)
    if (type(qos) == 'function') then
        callback = qos
        qos = nil
    end
    local q = qos or 0
    if (self.mc ~= nil) then self.mc:subscribe(topic, q, callback) end
end

function QNode:getAttrs(...)
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

function QNode:setAttrs(...) -- args: oid, iid, rid, attrs
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
function QNode:_target(oid, iid, rid)
    local tgtype, target

    if (oid ~= nil and oid == '') then tgtype = trgtype.root
    elseif (oid ~= nil) then tgtype = trgtype.object
        if (iid ~= nil) then tgtype = trgtype.instance
            if (rid ~= nil) then tgtype = trgtype.resource end
        end
    end

    if (tgtype == trgtype.object) then target = self:_dumpObject(oid)
    elseif (tgtype == trgtype.instance) then target = self:_dumpObject(oid, iid) 
    elseif (tgtype == trgtype.resource) then self:_rd(false, oid, iid, rid, function (err, val) target = val end)
    end

    if (target == nil) then target = tag.notfound end
    return tgtype, target
end

function QNode:_nextId(intf)
    local nextid = function ()
        self._tid = self._tid + 1
        if (self._tid > 255) then self._tid = 0 end
    end

    if (intf ~= nil) then
        local rspid = intf .. ':rsp:' .. tostring(self._tid)
        while self:listenerCount(rspid) ~= 0 do rspid = intf .. ':rsp:' .. tostring(nextid()) end
    end
    return self._tid
end

function QNode:_dumpObject(...)
    local oid, iid = ...
    local dump, obj = {}, self.so[oid]

    if (obj == nil) then dump = nil
    elseif (iid == nil) then        -- dump object
        for ii, inst in pairs(obj) do
            dump[ii] = {}
            for rid, resrc in pairs(obj[ii]) do self:readResrc(oid, ii, rid, function (err, val) dump[ii][rid] = val end) end
        end
    else                       -- dump instance
        if (obj[iid] == nil) then dump = nil
        else for rid, resrc in pairs(obj[iid]) do self:readResrc(oid, iid, rid, function (err, val) dump[rid] = val end) end
        end
    end

    return dump
end

function QNode:_rd(chk, oid, iid, rid, callback)
    local result
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid
    callback = callback or function(...) end

    if (self.so[oid] == nil or self.so[oid][iid] == nil or self.so[oid][iid][rid] == nil) then
        callback(core.ERR.nfnd, nil)
    else
        local resrc = self.so[oid][iid][rid]
        local rtype = type(resrc)
        if (rtype == 'table' and resrc._isCb == true) then
            if (type(resrc.read) == 'function') then
                pcall(resrc.read, function (err, val)
                    result = val
                    callback(err, val)
                end)
            elseif (type(resrc.exec) == 'function') then callback(core.ERR.unrd, tag.exec)
            else callback(core.ERR.unrd, core.TAG.unrd)
            end
        elseif (rtype == 'function' or rtype == 'thread') then
            callback(core.ERR.unrd, nil)
        else
            result = resrc
            callback(core.ERR.sces, resrc)
        end
    end

    if (chk == true and result ~= nil) then self:_chkResrc(oid, iid, rid, result) end
end

return QNode

-- ********************************************* --
-- **  Utility Methods                        ** --
-- ********************************************* --

--[[
function QNode:print()
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