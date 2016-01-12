local timer = require 'timer'
local _pubics, _subics, qn = {}, {}
local core = {
    RSP = { ok = 200, cre = 201, del = 202, chg = 204, ctn = 205, breq = 400, unauth = 401, nfnd = 404, nalw = 405, cnft = 409 },
    CMD = { r = 0, w = 1, dcv = 2, wa = 3, e = 4, ob = 5, noti = 6 },
    ERR = { sces = 0, nfnd = 1, unrd = 2, unwt = 3, une = 4, timeout = 5, nilclient = 6 },
    TTYPE = { rt = 0, obj = 1, inst = 2, rsc = 3 },
    TAG = { nfnd = '_notfound_', unrd = '_unreadable_', exec = '_exec_', unwt = '_unwritable_' },
    _tobjs = {}
}
-- ok
function core._rawHdlr(conn, topic, message)
    local strmsg, intf, jmsg, _evt = qn:decrypt(message), core._repath(topic)

    if (strmsg:sub(1, 1) == '{' and strmsg:sub(-1) == '}') then jmsg = cjson.decode(strmsg) end

    if (intf == _subics.register) then  _evt = 'register:rsp:' .. tostring(jmsg.transId)
        if (jmsg.status == RSP.ok or jmsg.status == RSP.cre) then qn:_lifeUpdate(true) else qn:_lifeUpdate(false) end
    elseif (intf == _subics.deregister) then _evt = 'deregister:rsp:' .. tostring(jmsg.transId)
    elseif (intf == _subics.notify) then _evt = 'notify:rsp:' .. tostring(jmsg.transId)
    elseif (intf == _subics.update) then _evt = 'update:rsp:' .. tostring(jmsg.transId)
    elseif (intf == _subics.ping) then _evt = 'ping:rsp:' .. tostring(jmsg.transId)
    elseif (intf == _subics.request) then _evt = '_request'                 -- No callbacks
    elseif (intf == _subics.announce) then _evt = 'announce' jmsg = strmsg  -- No callbacks
    end

    if (_evt ~= nil) then
        qn:emit(_evt, jmsg)
        if (core._tobjs[_evt] ~= nil) then timer.clearTimeout(core._tobjs[_evt]) end
    end
    qn:emit('message', topic, strmsg)    -- emit raw message out
end

function core._reqHdlr(msg)
    local rsp, rtn = { transId = msg.transId, cmdId = msg.cmdId, status = RSP.ok, data = nil }, true
    local tgtype, target = qn:_target(msg.oid, msg.iid, msg.rid)

    if (tgtype == TTYPE.rt or msg.oid == nil) then rsp.status = RSP.breq -- Request Root is not allowed
    elseif (target == TAG.nfnd) then rsp.status = RSP.nfnd
    else rtn = false
    end
    if (rtn == true) then qn:pubResponse(rsp) return end

    if (msg.cmdId == CMD.r) then
        if (target == TAG.unrd) then rsp.status = RSP.nalw
        else rsp.status = RSP.ctn
        end
        rsp.data = target
    elseif (msg.cmdId == CMD.w) then
        -- [TODO] 1. allow object and instance 2. tackle access control in the near future
        if (tgtype == TTYPE.obj or tgtype == TTYPE.inst) then    -- will support in the future
            rsp.status = RSP.nalw
        elseif (tgtype == TTYPE.rsc) then
            rsp.status = RSP.chg
            qn:writeResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, val)
                if (err == ERR.unwt) then rsp.status = RSP.nalw
                else rsp.data = val
                end
            end)
        end
    elseif (cmdId == CMD.dcv) then
        local export, attrs = {}
        if (tgtype == TTYPE.obj) then
            attrs = qn:getAttrs(msg.oid) or {}

            local obj, resrcList = qn.so[msg.oid], {}
            for iid, resrcs in pairs(obj) do
                resrcList[iid] = {}
                for rid, r in resrcs do table.insert(resrcList[iid], rid) end
            end
            attrs.resrcList = resrcList

        elseif (tgtype == TTYPE.inst) then attrs = qn:getAttrs(msg.oid, msg.iid)
        elseif (tgtype == TTYPE.rsc) then attrs = qn:getAttrs(msg.oid, msg.iid, msg.rid)
        end
        for k, v in pairs(attrs) do if (k ~= 'mute' and k ~= 'lastrp') then export[k] = v end end
        rsp.status = RSP.ctn
        rsp.data = export
    elseif (cmdId == CMD.wa) then
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
                    qn:setAttrs(msg.oid, msg.attrs)
                elseif (tgtype == TTYPE.inst) then
                    if (msg.attrs.cancel ~= nil) then msg.attrs.cancel = true end   -- [TODO] always avoid report, support in future
                    qn:setAttrs(msg.oid, msg.iid, msg.attrs)
                elseif (tgtype == TTYPE.rsc) then
                    if (msg.attrs.cancel) then qn:disableReport(msg.oid, msg.iid, msg.rid) end
                     qn:setAttrs(msg.oid, msg.iid, msg.rid, msg.attrs)
                else
                    rsp.status = RSP.nfnd
                end
            end
        end
    elseif (cmdId == CMD.e) then
        if (tgtype ~= TTYPE.rsc) then
            rsp.status = RSP.nalw
        else
            rsp.status = RSP.chg
            qn:execResrc(msg.oid, msg.iid, msg.rid, msg.data, function (err, execRsp)
                for k, v in pairs(execRsp) do rsp[k] = v end
            end)
        end
    elseif (cmdId == CMD.ob) then
        rsp.status = RSP.chg
        if (tgtype == TTYPE.obj or tgtype == TTYPE.inst) then
             rsp.status = RSP.nalw   -- [TODO] will support in the future
        elseif (tgtype == TTYPE.rsc) then
            qn:enableReport(msg.oid, msg.iid, msg.rid)
        end
    elseif (cmdId == CMD.noti) then
        return  -- notify, this is not a request, do nothing
    else
        rsp.status = RSP.breq -- unknown request
    end

    qn:pubResponse(rsp)
end

function core.register(qn)
    local intfs = { 'register', 'deregister', 'notify', 'update', 'ping' }
    qn = qn
    qn:on('raw', core._rawHdlr)
    qn:on('_request', core._reqHdlr)

    for i, itf in ipairs(intfs) do
        _pubics[itf] = itf .. '/' .. qn.clientId
        _subics[itf] = itf .. '/response/' .. qn.clientId
    end
    _pubics.response = 'response/' .. qn.clientId
    _subics.request = 'request/' .. qn.clientId
    _subics.announce = 'announce'

    qn.so = qn.so or {}
    -- LWM2M Object: LWM2M Server Object
    -- 0 = short server id, 1 = lifetime, 2 = default pmin, 3 = default pmax, 8 = registration update trigger
    qn.so[1] = { [0] = nil, [1] = qn.lifetime, [2] = 1, [3] = 60, [8] = { exec = function (...) end } }
    -- LWM2M Object: Device
    -- 0 = manuf, 1 = model, 4 = reboot, 5 = factory reset, 6 = available power sources,
    -- 7 = power source voltage, 17 = device type, 18 = hardware version, 19 = software version
    qn.so[3] = { [0] = 'freebird', [1] = 'mqtt-node',  [4] = { exec = function () node.restart() end },
                    [5] = { exec = function () end }, [6] = 0, [7] = 5000, [17] = 'generic', [18] = 'v0.0.1', [19] = 'v0.0.1' }
    -- LWM2M Object: Connectivity Monitoring
    -- 4 = ip, 5 = router ip
    qn.so[4] = { [4] = qn.ip, [5] = nil }
end

function qn:_lifeUpdate(enable)
    qn._lfCountSecs = 0

    if (qn._lfUpdater ~= nil) then
        timer.clearInterval(qn._lfUpdater)
        qn._lfUpdater = nil
    end

    if (enable == true) then
        qn._lfUpdater = timer.setInterval(function ()
            qn._lfCountSecs = qn._lfCountSecs + 1
            if (qn._lfCountSecs == qn.lifetime) then
                qn:pubUpdate({ lifetime = qn.lifetime })
                qn._lfCountSecs = 0
            end
        end, 1000)
    end
end

function qn:_chkResrc(oid, iid, rid, currVal)
    local attrs, rpt = qn:getAttrs(oid, iid, rid), false

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
        qn:pubNotify({ oid = oid, iid = iid, rid = rid, data = currVal })
    end

    return rpt
end

function qn:enableReport(oid, iid, rid, attrs)
    local tgtype, target = qn:_target(oid, iid, rid)
    if (target == TAG.nfnd) then return false end

    local resrcAttrs = qn:getAttrs(oid, iid, rid)
    local rpid = tostring(oid) .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    local pminMs, pmaxMs, rRpt = resrcAttrs.pmin * 1000, resrcAttrs.pmax * 1000 -- pmin and pmax are MUSTs

    resrcAttrs.cancel = false
    resrcAttrs.mute = true

    qn.reporters[rpid] = { minRep = nil, maxRep = nil, poller = nil } -- reporter place holder
    rRpt = qn.reporters[rpid]

    rRpt.minRep = timer.setTimeout(function ()  -- mute is use to control the poller
        if (pminMs == 0) then resrcAttrs.mute = false   -- if no pmin, just report at pmax triggered
        else qn:readResrc(oid, iid, rid, function (err, val)
                resrcAttrs.mute = false
                qn:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
            end)
        end
    end, pminMs)

    rRpt.maxRep = timer.setInterval(function ()
        resrcAttrs.mute = true
        qn:readResrc(oid, iid, rid, function (err, val)
            resrcAttrs.mute = false
            qn:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
        end)

        if (rRpt.minRep ~= nil) then timer.clearTimeout(rRpt.minRep) end
        rRpt.minRep = nil
        rRpt.minRep = timer.setTimeout(function ()
            if (pminMs == 0) then resrcAttrs.mute = false   --  if no pmin, just report at pmax triggered
            else qn:readResrc(oid, iid, rid, function (err, val)
                    resrcAttrs.mute = false
                    qn:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
                end)
            end
        end, pminMs)
    end, pmaxMs)

    return true
end

function qn:disableReport(oid, iid, rid)
    local rpid = tostring(oid) .. ':' .. tostring(iid) .. ':' .. tostring(rid)
    local resrcAttrs, rRpt = qn:getAttrs(oid, iid, rid), qn.reporters[rpid]

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
    qn.reporters[rpid] = nil
    return true
end

function MqttNode:_timeoutCtrl(key, delay)
    self._tobjs[key] = timer.setTimeout(function ()
        self:emit(key, { status = ERR.timeout })
        if (self._tobjs[key] ~= nil) then self._tobjs[key] = nil end
    end, delay)
end


function core._repath(path)
    local head, tail = 1, #path
    path = path:gsub("%.", "/")
    if (path:sub(1, 1) == '/') then head = 2 end
    if (path:sub(#path, #path) == '/') then tail = tail - 1 end
    return path:sub(head, tail)
end

return core