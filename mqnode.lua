------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENSE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------
local M = {}
local tm, lock, ttbl, exec = { id = 6, enable = false, tick = 1000 }, false, {}, {}
local RSP = { ok = 200, cre = 201, del = 202, chg = 204, ctn = 205, breq = 400, unauth = 401, nfnd = 404, nalw = 405, cnft = 409 }
local CMD = { r = 0, w = 1, dcv = 2, wa = 3, e = 4, ob = 5, noti = 6 }
local ERR = { sces = 0, nfnd = 1, unrd = 2, unwt = 3, une = 4, timeout = 5, nilclient = 6 }
local TTYPE = { rt = 0, obj = 1, inst = 2, rsc = 3 }
local TAG = { nfnd = '_notfound_', unrd = '_unreadable_', exec = '_exec_', unwt = '_unwritable_' }
local _pubics, _subics
local _sec = 60
local PFX = '_n_'
local PFX_LEN = #PFX

function M:new(n)
    n = n or {}
    assert(type(n.mac) == 'string', "mac should be a string.")
    assert(type(n.ip) == 'string', "ip should be a string.")
    n.clientId = n.clientId or 'qn-' .. n.mac
    n.lifetime = n.lifetime or 86400
    n.version = n.version or '0.0.1'
    n.mc = nil
    n.so = {}

    -- LWM2M Object: LWM2M Server Object
    -- 0 = short server id, 1 = lifetime, 2 = default pmin, 3 = default pmax, 8 = registration update trigger
    n.so[1] = { [0] = nil, [1] = n.lifetime, [2] = 1, [3] = 60, [8] = { exec = function (...) n:pubRegister() end } }
    -- LWM2M Object: Device
    -- 0 = manuf, 1 = model, 4 = reboot, [X]5 = factory reset, 6 = available power sources,
    -- 7 = power source voltage, 17 = device type, 18 = hardware version, 19 = software version
    n.so[3] = { [0] = 'lwmqn', [1] = 'MQ1',  [4] = { exec = function () node.restart() end },
                 [6] = 0, [7] = 5000, [17] = 'generic', [18] = 'v1', [19] = 'v1' }
    -- LWM2M Object: Connectivity Monitoring
    -- 4 = ip, 5 = router ip
    n.so[4] = { [4] = n.ip, [5] = '' }

    n._tid = 0
    n._repAttrs = {}
    n._tobjs = {}
    n._lfsecs = 0
    n._upder = nil
    n._rpters = {}
    n._on = {}
    n.timer = tm
    
    n:on('raw', function (...) self:_rawHdlr(...) end)
    n:on('_request', function (...) self:_reqHdlr(...) end)

    local intfs, cId = { 'register', 'deregister', 'notify', 'update', 'ping' }, n.clientId
    for i, itf in ipairs(intfs) do
        _pubics[itf] = itf .. '/' .. cId
        _subics[itf] = itf .. '/response/' .. cId
    end
    _pubics.response = 'response/' .. cId
    _subics.request = 'request/' .. cId
    _subics.announce = 'announce'

    self.__index = self
    n = setmetatable(n, self)
    return n
end

function M:encrypt(msg)
    return msg
end

function M:decrypt(msg)
    return msg
end

function M:changeIp(ip)
    local n = self
    if (ip ~= n.ip) then
        n.ip = ip
        n.so[4][4] = n.ip
        n:pubUpdate({ ip = n.ip })
    end
end

function M:initResrc(...)
    local n = self
    local oid, iid, resrcs = ...
    oid = tonumber(oid) or oid
    iid = tonumber(iid) or iid
    n.so[oid] = n.so[oid] or {}
    n.so[oid][iid] = n.so[oid][iid] or {}

    for rid, rval in pairs(resrcs) do
        if (type(rval) ~= 'function') then
            n.so[oid][iid][rid] = rval
            if (type(rval) == 'table') then
                rval._isCb = type(rval.read) == 'function' or type(rval.write) == 'function' or type(rval.exec) == 'function'
            end
        end
    end
    return n
end

function M:getAttrs(...)
    local n = self
    local oid, iid, rid = ...
    local tgtype, target, key, attrs = n:_target(...), tostring(oid)
    local default = { pmin = n.so[1][2], pmax = n.so[1][3], mute = true, cancel = true }

    if (target == TAG.nfnd) then return nil end
    if (tgtype == TTYPE.obj) then key = key
    elseif (tgtype == TTYPE.inst) then key = key .. ':' .. iid
    elseif (tgtype == TTYPE.rsc) then key = key .. ':' .. iid .. ':' .. rid
    end
    n._repAttrs[key] = n._repAttrs[key] or default

    return n._repAttrs[key]
end

function M:setAttrs(...) -- args: oid, iid, rid, attrs
    local argtbl = { ... }
    local oid, key = argtbl[1], tostring(argtbl[1])
    local iid, rid, tgtype, target, attrs

    if (#argtbl == 4) then
        iid, rid, attrs = argtbl[2], argtbl[3], argtbl[4]
        key = key .. ':' .. iid .. ':' .. rid
    elseif (#argtbl == 3) then
        iid, attrs = argtbl[2], argtbl[3]
        key = key .. ':' .. iid
    elseif (#argtbl == 2) then
        attrs = argtbl[2]
    end

    tgtype, target = self:_target(oid, iid, rid)
    if (target == TAG.nfnd) then return false end
    attrs.pmin = attrs.pmin or self.so[1][2]
    attrs.pmax = attrs.pmax or self.so[1][3]
    self._repAttrs[key] = attrs
    return true
end

function M:readResrc(oid, iid, rid, callback)
    return self:_rd(true, oid, iid, rid, callback)
end

function M:writeResrc(oid, iid, rid, value, callback)
    local n, result = self
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid
    callback = callback or function(...) end

    if (n:_has(oid, iid, rid)) then
        local resrc = n.so[oid][iid][rid]
        local rtype = type(resrc)
        if (rtype == 'table') then
            if (resrc._isCb) then
                if (type(resrc.write) == 'function') then
                    pcall(resrc.write, value, function (err, val)
                        result = val
                        callback(err, val)
                    end)
                else callback(ERR.unwt, nil)
                end
            else
                n.so[oid][iid][rid] = value
                result = value
                callback(ERR.sces, value)
            end
        elseif (rtype == 'function' or rtype == 'thread') then
            callback(ERR.unwt, nil)
        else
            n.so[oid][iid][rid] = value
            result = value
            callback(ERR.sces, value)
        end
    else
        callback(ERR.nfnd, nil)
    end
    if (result ~= nil) then n:_chkResrc(oid, iid, rid, result) end
end

function M:execResrc(oid, iid, rid, argus, callback)
    callback = callback or function(...) end
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid

    if (self:_has(oid, iid, rid)) then
        local resrc = self.so[oid][iid][rid]
        if (type(resrc) ~= 'table' or type(resrc.exec) ~= 'function') then callback(ERR.une, { status = RSP.nalw })
        else pcall(resrc.exec, argus, callback) -- unpack by their own, resrc.exec(args, callback)
        end
    else
        callback(ERR.nfnd, { status = RSP.nfnd })
    end
end

function M:connect(url, opts)
    local n = self
    opts = opts or {}
    if (n.mc == nil) then
        n.mc = mqtt.Client(n.clientId, opts.keepalive or 120, opts.username or 'freebird', opts.password or 'skynyrd', opts.cleansession or 1)
    end

    n.mc:connect(url, opts.port or 1883, opts.secure or 0, function (c)
        n.mc:on('message', function (client, topic, msg) n:emit('raw', client, topic, msg) end)
    end)
end

function M:close(callback)
    if (self.mc ~= nil) then self.mc:close() end
    if (callback ~= nil) then callback() end
end

function M:pubRegister(callback)
    local n = self
    local data = { transId = nil, lifetime = n.lifetime, objList = {},
                      ip = n.ip, mac = n.mac, version = n.version }

    for oid, obj in pairs(n.so) do
        for iid, _ in pairs(obj) do table.insert(data.objList, { oid = oid, iid = iid }) end
    end

    return n:_pubReq('register', data)
end

function M:pubDeregister(callback)
    return self:_pubReq('deregister', { data = nil })
end

function M:pubNotify(data, callback)
    return self:_pubReq('notify', data, function (err, rsp)
        if (rsp.cancel) then self:disableReport(data.oid, data.iid, data.rid) end
        if (callback ~= nil) then callback(err, rsp) end
    end)
end

function M:pingServer(callback)
    return self:_pubReq('ping', { data = nil })
end

function M:pubUpdate(devAttrs, callback)
    return self:_pubReq('update', devAttrs)
end

function M:pubResponse(rsp, callback)
    return self:publish(self._pubics.response, rsp, callback)
end

function M:publish(topic, message, options, callback)
    if (type(options) == 'function') then
        callback = options
        options = nil
    end
    local qos, retain, jmsg = options.qos or 0, options.retain or 0, message

    if (type(message) == 'table') then message = cjson.encode(message) end

    self.mc:publish(topic, self:encrypt(message), qos, retain, function (client)
        self:emit('published', { topic = topic, message = jmsg, options = options })
        if (callback ~= nil) then callback() end
    end)
end

function M:subscribe(topic, qos, callback)
    if (type(qos) == 'function') then
        callback = qos
        qos = nil
    end
    self.mc:subscribe(topic, qos or 0, callback)
end

-- ********************************************* --
-- **  Protected Methods                      ** --
-- ********************************************* --
function M:_pubReq(intf, data, callback)
    local n = self
    data.transId = n:_id(intf)
    if (callback ~= nil) then
        local key = intf .. ':rsp:' .. data.transId
        n:_tmout(key, _sec)
        n:once(key, callback)
    end

    return n:publish(n._pubics[intf], data)
end

function M:_target(oid, iid, rid)
    local tgtype, target

    if (oid ~= nil and oid == '') then tgtype = TTYPE.rt
    elseif (oid ~= nil) then tgtype = TTYPE.obj
        if (iid ~= nil) then tgtype = TTYPE.inst
            if (rid ~= nil) then tgtype = TTYPE.rsc end
        end
    end

    if (tgtype == TTYPE.obj) then target = self:_dumpObj(oid)
    elseif (tgtype == TTYPE.inst) then target = self:_dumpObj(oid, iid) 
    elseif (tgtype == TTYPE.rsc) then self:_rd(false, oid, iid, rid, function (err, val) target = val end)
    end

    if (target == nil) then target = TAG.nfnd end
    return tgtype, target
end

function M:_id(intf)
    local n = self
    local nextid = function ()
        n._tid = n._tid + 1
        if (n._tid > 255) then n._tid = 0 end
        return n._tid
    end

    if (intf ~= nil) then
        local rspid = intf .. ':rsp:' .. n._tid
        while n._on[rspid .. ':_'] ~= nil or n._on[rspid] ~= nil do rspid = intf .. ':rsp:' .. nextid() end
    end
    return n._tid
end

function M:_dumpObj(...)
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

function M:_rd(chk, oid, iid, rid, callback)
    local result
    oid = tonumber(oid) or oid
    rid = tonumber(rid) or rid
    callback = callback or function(...) end

    if (self:_has(oid, iid, rid)) then
        local resrc = self.so[oid][iid][rid]
        local rtype = type(resrc)
        if (rtype == 'table' and resrc._isCb == true) then
            if (type(resrc.read) == 'function') then
                pcall(resrc.read, function (err, val)
                    result = val
                    callback(err, val)
                end)
            elseif (type(resrc.exec) == 'function') then callback(ERR.unrd, TAG.exec)
            else callback(ERR.unrd, TAG.unrd)
            end
        elseif (rtype == 'function' or rtype == 'thread') then
            callback(ERR.unrd, nil)
        else
            result = resrc
            callback(ERR.sces, resrc)
        end
    else
        callback(ERR.nfnd, nil)
    end

    if (chk == true and result ~= nil) then self:_chkResrc(oid, iid, rid, result) end
end

function M:_has(oid, iid, rid)
    return self.so[oid] ~= nil and self.so[oid][iid] ~= nil and self.so[oid][iid][rid] ~= nil
end

------------------------------------------------------------------------------
-- Core 
------------------------------------------------------------------------------
function M:_rawHdlr(conn, topic, message)
    local n = self
    local strmsg, intf, jmsg, _evt, tid = n:decrypt(message), n:_path(topic)

    if (strmsg:sub(1, 1) == '{' and strmsg:sub(-1) == '}') then
        jmsg = cjson.decode(strmsg)
        tid = jmsg.transId
    end

    if (intf == _subics.register) then  _evt = 'register:rsp:' .. tid
        if (jmsg.status == RSP.ok or jmsg.status == RSP.cre) then n:_lfUp(true) else n:_lfUp(false) end
    elseif (intf == _subics.deregister) then _evt = 'deregister:rsp:' .. tid
    elseif (intf == _subics.notify) then _evt = 'notify:rsp:' .. tid
    elseif (intf == _subics.update) then _evt = 'update:rsp:' .. tid
    elseif (intf == _subics.ping) then _evt = 'ping:rsp:' .. tid
    elseif (intf == _subics.request) then _evt = '_request'                 -- No callbacks
    elseif (intf == _subics.announce) then _evt = 'announce' jmsg = strmsg  -- No callbacks
    end

    if (_evt ~= nil) then
        n:emit(_evt, jmsg)
        if (n._tobjs[_evt] ~= nil) then tm.clear(n._tobjs[_evt]) end
    end
    n:emit('message', topic, strmsg)    -- emit raw message out
end

function M:_reqHdlr(msg)
    local n = self
    local rsp, rtn = { transId = msg.transId, cmdId = msg.cmdId, status = RSP.ok, data = nil }, true
    local tgtype, target = n:_target(msg.oid, msg.iid, msg.rid)

    if (tgtype == TTYPE.rt or msg.oid == nil) then rsp.status = RSP.breq -- Request Root is not allowed
    elseif (target == TAG.nfnd) then rsp.status = RSP.nfnd
    else rtn = false
    end

    if (rtn == true) then n:pubResponse(rsp) return end

    if (msg.cmdId == CMD.r) then        -- READ Handler
        if (target == TAG.unrd) then rsp.status = RSP.nalw
        else rsp.status = RSP.ctn
        end
        rsp.data = target
    elseif (msg.cmdId == CMD.w) then    -- WRITE Handler
        -- [TODO] 1. allow object and instance 2. tackle access control in the near future
        if (tgtype == TTYPE.obj or tgtype == TTYPE.inst) then
            rsp.status = RSP.nalw
        elseif (tgtype == TTYPE.rsc) then
            rsp.status = RSP.chg
            n:writeResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, val)
                if (err == ERR.unwt) then rsp.status = RSP.nalw
                else rsp.data = val
                end
            end)
        end
    elseif (cmdId == CMD.dcv) then      -- DISCOVER Handler
        local export, attrs = {}
        if (tgtype == TTYPE.obj) then
            attrs = n:getAttrs(msg.oid) or {}

            local obj, resrcList = n.so[msg.oid], {}
            for iid, resrcs in pairs(obj) do
                resrcList[iid] = {}
                for rid, r in resrcs do table.insert(resrcList[iid], rid) end
            end
            attrs.resrcList = resrcList

        elseif (tgtype == TTYPE.inst) then attrs = n:getAttrs(msg.oid, msg.iid)
        elseif (tgtype == TTYPE.rsc) then attrs = n:getAttrs(msg.oid, msg.iid, msg.rid)
        end
        for k, v in pairs(attrs) do if (k ~= 'mute' and k ~= 'lastrp') then export[k] = v end end
        rsp.status = RSP.ctn
        rsp.data = export
    elseif (cmdId == CMD.wa) then       -- WRITE ATTRIBUTES Handler
        local badAttr = false
        local allowedAttrsMock = { pmin = true, pmax = true, gt = true, lt = true, step = true, cancel = true, pintvl = true }

        if (msg.attrs ~= 'table') then
            rsp.status = RSP.breq
        else
            for k, v in pairs(msg.attrs) do if (allowedAttrsMock[k] ~= true) then badAttr = true end end
            if (badAttr == true) then
                rsp.status = RSP.breq
            else
                rsp.status = RSP.chg
                if (tgtype == TTYPE.obj) then
                    if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end   -- [TODO] always avoid report, support in future
                    n:setAttrs(msg.oid, msg.attrs)
                elseif (tgtype == TTYPE.inst) then
                    if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end   -- [TODO] always avoid report, support in future
                    n:setAttrs(msg.oid, msg.iid, msg.attrs)
                elseif (tgtype == TTYPE.rsc) then
                    if (msg.attrs.cancel) then n:disableReport(msg.oid, msg.iid, msg.rid) end
                     n:setAttrs(msg.oid, msg.iid, msg.rid, msg.attrs)
                else
                    rsp.status = RSP.nfnd
                end
            end
        end
    elseif (cmdId == CMD.e) then        -- EXECUTE Handler
        if (tgtype ~= TTYPE.rsc) then
            rsp.status = RSP.nalw
        else
            rsp.status = RSP.chg
            n:execResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, execRsp)
                for k, v in pairs(execRsp) do rsp[k] = v end
            end)
        end
    elseif (cmdId == CMD.ob) then       -- OBSERVE Handler
        rsp.status = RSP.chg
        if (tgtype == TTYPE.obj or tgtype == TTYPE.inst) then
             rsp.status = RSP.nalw   -- [TODO] will support in the future
        elseif (tgtype == TTYPE.rsc) then
            n:enableReport(msg.oid, msg.iid, msg.rid)
        end
    elseif (cmdId == CMD.noti) then     -- NOTIFY Handler
        return  -- notify, this is not a request, do nothing
    else                                -- UNKNOWN CMD Handler
        rsp.status = RSP.breq -- unknown request
    end

    n:pubResponse(rsp)
end

function M:_lfUp(enable)
    local n = self
    n._lfsecs = 0
    tm.clear(n._upder)
    n._upder = nil

    if (enable == true) then
        n._upder = tm.setInterval(function ()
            n._lfsecs = n._lfsecs + 1
            if (n._lfsecs == n.lifetime) then
                n:pubUpdate({ lifetime = n.lifetime })
                n._lfsecs = 0
            end
        end, 1)
    end
end

function M:_chkResrc(oid, iid, rid, currVal)
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

function M:enableReport(oid, iid, rid, attrs)
    local n = self
    local tgtype, target = n:_target(oid, iid, rid)
    if (target == TAG.nfnd) then return false end

    local resrcAttrs = n:getAttrs(oid, iid, rid)
    local rpid = oid .. ':' .. iid .. ':' .. rid
    local pmin, pmax, rRpt = resrcAttrs.pmin, resrcAttrs.pmax -- pmin and pmax are MUSTs

    resrcAttrs.cancel = false
    resrcAttrs.mute = true

    n._rpters[rpid] = { min = nil, max = nil, poller = nil } -- reporter place holder
    rRpt = n._rpters[rpid]

    rRpt.min = tm.setTimeout(function ()  -- mute is use to control the poller
        if (pmin == 0) then resrcAttrs.mute = false   -- if no pmin, just report at pmax triggered
        else n:readResrc(oid, iid, rid, function (err, val)
                resrcAttrs.mute = false
                n:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
            end)
        end
    end, pmin)

    rRpt.max = tm.setInterval(function ()
        resrcAttrs.mute = true
        n:readResrc(oid, iid, rid, function (err, val)
            resrcAttrs.mute = false
            n:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
        end)

        if (rRpt.min ~= nil) then tm.clear(rRpt.min) end
        rRpt.min = nil
        rRpt.min = tm.setTimeout(function ()
            if (pmin == 0) then resrcAttrs.mute = false   --  if no pmin, just report at pmax triggered
            else n:readResrc(oid, iid, rid, function (err, val)
                    resrcAttrs.mute = false
                    n:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
                end)
            end
        end, pmin)
    end, pmax)

    return true
end

function M:disableReport(oid, iid, rid)
    local rpid = oid .. ':' .. iid .. ':' .. rid
    local resrcAttrs, rRpt = self:getAttrs(oid, iid, rid), self._rpters[rpid]

    if (rRpt == nil) then return false end
    if (resrcAttrs == nil) then return false end

    resrcAttrs.cancel = true
    resrcAttrs.mute = true

    tm.clear(rRpt.min)
    tm.clear(rRpt.max)
    tm.clear(rRpt.poller)
    rRpt.min = nil
    rRpt.max = nil
    rRpt.poller = nil
    self._rpters[rpid] = nil
    return true
end

function M:_tmout(key, delay)
    self._tobjs[key] = tm.setTimeout(function ()
        self:emit(key, { status = ERR.timeout })
        self._tobjs[key] = nil
    end, delay)
end

function M:_path(path)
    local head, tail = 1, #path
    path = path:gsub("%.", "/")
    if (path:sub(1, 1) == '/') then head = 2 end
    if (path:sub(#path, #path) == '/') then tail = tail - 1 end
    return path:sub(head, tail)
end

------------------------------------------------------------------------------
-- Tm Utility
------------------------------------------------------------------------------
local function rm(tbl, pred)
    if (pred == nil) then return tbl end
    local x, len = 0, #tbl
    for i = 1, len do
        local trusy, idx = false, (i - x)
        if (type(pred) == 'function') then trusy = pred(tbl[idx])
        else trusy = tbl[idx] == pred
        end

        if (trusy) then
            table.remove(tbl, idx)
            x = x + 1
        end
    end
    return tbl
end

local function chk()
    if (lock) then return else lock = true end
    if (#ttbl == 0) then tm.stop() return end

    for i, tob in ipairs(ttbl) do
        tob.delay = tob.delay - 1
        if (tob.delay == 0) then
            if (tob.rp > 0) then tob.delay = tob.rp end
            table.insert(exec, tob)
        end
    end

    for ii, tt in ipairs(exec) do
        rm(ttbl, tt)
        local status, err = pcall(tt.f, unpack(tt.argus))
        if not (status) then print("Task execution fails: " .. tostring(err)) end
        if (tt.delay > 0) then table.insert(ttbl, tt) end
        exec[ii] = nil
    end
    lock = false
end

function tm.start()
    tmr.alarm(tm.id, tm.tick, 1, chk)   -- tid = 6, intvl = 2ms, repeat = 1
    tm.enable = true
end

function tm.stop()
    tmr.stop(tm.id)
    tm.enable = false
    ttbl = rm(ttbl, function (v) return v ~= nil end)
    lock = false
end

function tm.set(tid)
    if (tid ~= tm.id) then
        tm.stop()
        tm.id = tid
        tm.start()
    end
end

function tm.setTimeout(fn, delay, ...)
    local tobj = { delay = delay, f = fn, rp = 0, argus = {...} }
    if (delay < 2) then tobj.delay = 1 end

    table.insert(ttbl, tobj)
    if (not tm.enable) then tm.start() end
    return tobj
end

function tm.setInterval(fn, delay, ...)
    local tobj = tm.setTimeout(fn, delay, ...)
    tobj.rp = tobj.delay
    return tobj
end

function tm.clear(tobj)
    tobj.rp = 0
    rm(exec, tobj)
    rm(ttbl, tobj)
end

------------------------------------------------------------------------------
-- EventEmitter
------------------------------------------------------------------------------
function M:_evtb(ev)
    self._on[ev] = self._on[ev] or {}
    return self._on[ev]
end

function M:on(ev, listener)
    table.insert(self:_evtb(PFX .. tostring(ev)), listener)
    return self
end

function M:emit(ev, ...)
    local pfx_ev, argus = PFX .. tostring(ev), {...}
    local evtbl = self._on[pfx_ev]

    local function exec(tbl)
        for _, lsn in ipairs(tbl) do
            local status, err = pcall(lsn, unpack(argus))
            if not (status) then print(string.sub(_, PFX_LEN + 1) .. " emit error: " .. tostring(err)) end
        end
    end

    if (evtbl ~= nil) then exec(evtbl) end

    -- one-time listener
    pfx_ev = pfx_ev .. ':_'
    evtbl = self._on[pfx_ev]

    if (evtbl ~= nil) then
        exec(evtbl)
        rm(evtbl, function (v) return v ~= nil  end)
        self._on[pfx_ev] = nil
    end
    return self
end

function M:once(ev, listener)
    table.insert(self:_evtb(PFX .. tostring(ev) .. ':_'), listener)
    return self
end

function M:removeAll(ev)
    if ev ~= nil then
        local pfx_ev = PFX .. tostring(ev)
        local evtbl = self:_evtb(pfx_ev)
        rm(evtbl, function (v) return v ~= nil  end)

        pfx_ev = pfx_ev .. ':_'
        evtbl = self:_evtb(pfx_ev)
        rm(evtbl, function (v) return v ~= nil  end)
        self._on[pfx_ev] = nil
    else
        for _pfx_ev, _t in pairs(self._on) do self:removeAll(string.sub(_pfx_ev, PFX_LEN + 1)) end
    end

    for _pfx_ev, _t in pairs(self._on) do
        if (#_t == 0) then self._on[_pfx_ev] = nil end
    end

    return self
end

function M:remove(ev, listener)
    local pfx_ev = PFX .. tostring(ev)
    local evtbl = self:_evtb(pfx_ev)
    local lsnCount = 0
    -- normal listener
    rm(evtbl, listener)
    if (#evtbl == 0) then self._on[pfx_ev] = nil end

    -- emit-once listener
    pfx_ev = pfx_ev .. ':_'
    evtbl = self:_evtb(pfx_ev)
    rm(evtbl, listener)
    if (#evtbl == 0) then self._on[pfx_ev] = nil end

    return self
end

return M
