
function MqttNode:new(qnode)
function MqttNode:setDevAttrs(devAttrs)
function MqttNode:initResrc(...)
function MqttNode:readResrc(oid, iid, rid, callback)
function MqttNode:writeResrc(oid, iid, rid, value, callback)
function MqttNode:execResrc(oid, iid, rid, value, callback)

function MqttNode:dump()
function MqttNode:objectList()

function MqttNode:encrypt(msg)
function MqttNode:decrypt(msg)
function MqttNode:resrcList(oid)
function MqttNode:connect(url, opts)

function MqttNode:pubRegister(callback)
function MqttNode:pubDeregister(callback)
function MqttNode:pubNotify(data, callback)
function MqttNode:pingServer(callback)
function MqttNode:pubUpdate(devAttrs, callback)
function MqttNode:pubResponse(rsp, callback)
function MqttNode:publish(topic, message, qos, retain, callback)

function MqttNode:getAttrs(...)
function MqttNode:setAttrs(...)
_findAttrs

function MqttNode:_target(oid, iid, rid)
function MqttNode:_initResrc(oid, iid, rid, value)
function MqttNode:_assignIid(objTbl)
function MqttNode:_deferIntfCallback(intf, transId, callback)
function MqttNode:_getIntfCallback(intf, transId)
function MqttNode:_nextTransId(intf)
function MqttNode:_dumpInstance(oid, iid)
function MqttNode:_dumpObject(oid)

function MqttNode:_buildDefaultSo()

function MqttNode:_startLifeUpdater()
function MqttNode:_stopLifeUpdater()
function MqttNode:_checkAndReportResrc(rid, currentValue)

function MqttNode:enableReport(oid, iid, rid)
function MqttNode:disableReport(oid, iid, rid)

function MqttNode:_readResrc(oid, iid, rid, callback)