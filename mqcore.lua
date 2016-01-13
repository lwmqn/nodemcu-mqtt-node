local timer = require 'timer'
local _pubics, _subics, qn = {}, {}

local RSP = { ok = 200, cre = 201, del = 202, chg = 204, ctn = 205, breq = 400, unauth = 401, nfnd = 404, nalw = 405, cnft = 409 }
local CMD = { r = 0, w = 1, dcv = 2, wa = 3, e = 4, ob = 5, noti = 6 }
local ERR = { sces = 0, nfnd = 1, unrd = 2, unwt = 3, une = 4, timeout = 5, nilclient = 6 }
local TTYPE = { rt = 0, obj = 1, inst = 2, rsc = 3 }
local TAG = { nfnd = '_notfound_', unrd = '_unreadable_', exec = '_exec_', unwt = '_unwritable_' }

local core = {
    RSP = RSP,
    CMD = CMD,
    ERR = ERR,
    TTYPE = TTYPE,
    TAG = TAG
}
-- ok
function core._rawHdlr(conn, topic, message)
    local strmsg, intf, jmsg, _evt, tid = qn:decrypt(message), core._path(topic)

    if (strmsg:sub(1, 1) == '{' and strmsg:sub(-1) == '}') then
        jmsg = cjson.decode(strmsg)
        tid = jmsg.transId
    end

    if (intf == _subics.register) then  _evt = 'register:rsp:' .. tid
        if (jmsg.status == RSP.ok or jmsg.status == RSP.cre) then qn:_lfUp(true) else qn:_lfUp(false) end
    elseif (intf == _subics.deregister) then _evt = 'deregister:rsp:' .. tid
    elseif (intf == _subics.notify) then _evt = 'notify:rsp:' .. tid
    elseif (intf == _subics.update) then _evt = 'update:rsp:' .. tid
    elseif (intf == _subics.ping) then _evt = 'ping:rsp:' .. tid
    elseif (intf == _subics.request) then _evt = '_request'                 -- No callbacks
    elseif (intf == _subics.announce) then _evt = 'announce' jmsg = strmsg  -- No callbacks
    end

    if (_evt ~= nil) then
        qn:emit(_evt, jmsg)
        if (qn._tobjs[_evt] ~= nil) then timer.clearTimeout(qn._tobjs[_evt]) end
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

function core.register(q)
    local intfs, cId = { 'register', 'deregister', 'notify', 'update', 'ping' }
    qn = q
    qn:on('raw', core._rawHdlr)
    qn:on('_request', core._reqHdlr)

    cId = qn.clientId
    for i, itf in ipairs(intfs) do
        _pubics[itf] = itf .. '/' .. cId
        _subics[itf] = itf .. '/response/' .. cId
    end
    _pubics.response = 'response/' .. cId
    _subics.request = 'request/' .. cId
    _subics.announce = 'announce'

    qn.so = qn.so or {}
    -- LWM2M Object: LWM2M Server Object
    -- 0 = short server id, 1 = lifetime, 2 = default pmin, 3 = default pmax, 8 = registration update trigger
    qn.so[1] = { [0] = nil, [1] = qn.lifetime, [2] = 1, [3] = 60, [8] = { exec = function (...) qn.pubRegister() end } }
    -- LWM2M Object: Device
    -- 0 = manuf, 1 = model, 4 = reboot, [X]5 = factory reset, 6 = available power sources,
    -- 7 = power source voltage, 17 = device type, 18 = hardware version, 19 = software version
    qn.so[3] = { [0] = 'lwmqn', [1] = 'MQ1',  [4] = { exec = function () node.restart() end },
                 [6] = 0, [7] = 5000, [17] = 'generic', [18] = 'v1', [19] = 'v1' }
    -- LWM2M Object: Connectivity Monitoring
    -- 4 = ip, 5 = router ip
    qn.so[4] = { [4] = qn.ip, [5] = '' }

    -- load protected methods
    qn._lfUp = function (q, enable)
        q._lfsecs = 0
        timer.clearInterval(q._upder)
        q._upder = nil

        if (enable == true) then
            q._upder = timer.setInterval(function ()
                q._lfsecs = q._lfsecs + 1
                if (q._lfsecs == q.lifetime) then
                    q:pubUpdate({ lifetime = q.lifetime })
                    q._lfsecs = 0
                end
            end, 1000)
        end
    end

    qn._chkResrc = function (q, oid, iid, rid, currVal)
        local attrs, rpt = q:getAttrs(oid, iid, rid), false

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
            q:pubNotify({ oid = oid, iid = iid, rid = rid, data = currVal })
        end

        return rpt
    end

    qn.enableReport = function (q, oid, iid, rid, attrs)
        local tgtype, target = q:_target(oid, iid, rid)
        if (target == TAG.nfnd) then return false end

        local resrcAttrs = q:getAttrs(oid, iid, rid)
        local rpid = oid .. ':' .. iid .. ':' .. rid
        local pminMs, pmaxMs, rRpt = resrcAttrs.pmin * 1000, resrcAttrs.pmax * 1000 -- pmin and pmax are MUSTs

        resrcAttrs.cancel = false
        resrcAttrs.mute = true

        q._rpters[rpid] = { minRep = nil, maxRep = nil, poller = nil } -- reporter place holder
        rRpt = q._rpters[rpid]

        rRpt.minRep = timer.setTimeout(function ()  -- mute is use to control the poller
            if (pminMs == 0) then resrcAttrs.mute = false   -- if no pmin, just report at pmax triggered
            else q:readResrc(oid, iid, rid, function (err, val)
                    resrcAttrs.mute = false
                    q:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
                end)
            end
        end, pminMs)

        rRpt.maxRep = timer.setInterval(function ()
            resrcAttrs.mute = true
            q:readResrc(oid, iid, rid, function (err, val)
                resrcAttrs.mute = false
                q:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
            end)

            if (rRpt.minRep ~= nil) then timer.clearTimeout(rRpt.minRep) end
            rRpt.minRep = nil
            rRpt.minRep = timer.setTimeout(function ()
                if (pminMs == 0) then resrcAttrs.mute = false   --  if no pmin, just report at pmax triggered
                else q:readResrc(oid, iid, rid, function (err, val)
                        resrcAttrs.mute = false
                        q:pubNotify({ oid = oid, iid = iid, rid = rid, data = val })
                    end)
                end
            end, pminMs)
        end, pmaxMs)

        return true
    end

    qn.disableReport = function (q, oid, iid, rid)
        local rpid = oid .. ':' .. iid .. ':' .. rid
        local resrcAttrs, rRpt = q:getAttrs(oid, iid, rid), q._rpters[rpid]

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
        q._rpters[rpid] = nil
        return true
    end

    qn._tCtrl = function (q, key, delay)
        q._tobjs[key] = timer.setTimeout(function ()
            qn:emit(key, { status = ERR.timeout })
            if (q._tobjs[key] ~= nil) then q._tobjs[key] = nil end
        end, delay)
    end
end

function core._path(path)
    local head, tail = 1, #path
    path = path:gsub("%.", "/")
    if (path:sub(1, 1) == '/') then head = 2 end
    if (path:sub(#path, #path) == '/') then tail = tail - 1 end
    return path:sub(head, tail)
end

return core