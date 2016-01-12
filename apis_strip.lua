
ok function MqttNode:new(qnode)
ok function MqttNode:setIp(ip)
ok function MqttNode:initResrc(...)	-- iid should be given, resrcs should be a table
ok function MqttNode:readResrc(oid, iid, rid, callback) 	
ok function MqttNode:writeResrc(oid, iid, rid, value, callback)
ok function MqttNode:execResrc(oid, iid, rid, value, callback)  -- [?] arg

ok function MqttNode:encrypt(msg)
ok function MqttNode:decrypt(msg)

ok function MqttNode:connect(url, opts)
ok function MqttNode:close(callback)

ok function MqttNode:_rawMessageHandler(conn, topic, message)
ok function MqttNode:_requestHandler(msg)
ok function MqttNode:enableReport(oid, iid, rid)
ok function MqttNode:disableReport(oid, iid, rid)

function MqttNode:pubRegister(callback)			-- use pub
function MqttNode:pubDeregister(callback)		-- use pub
function MqttNode:pingServer(callback)			-- use pub

function MqttNode:pubNotify(data, callback)		-- use pub
function MqttNode:pubUpdate(devAttrs, callback)	-- use pub
function MqttNode:pubResponse(rsp, callback)		-- use pub


ok function MqttNode:publish(topic, message, qos, retain, callback)
ok function MqttNode:subscribe(topic, qos, callback)

ok function MqttNode:getAttrs(...)   nil for notfound, default if empty, yes if there
ok function MqttNode:setAttrs(...)
-- _findAttrs

ok function MqttNode:_target(oid, iid, rid)
ok function MqttNode:_nextTransId(intf)
-- function MqttNode:_dumpInstance(oid, iid)
ok function MqttNode:_dumpObject(oid)

function MqttNode:_buildDefaultSo()

ok function MqttNode:_lifeUpdate(enable)
ok function MqttNode:_checkAndReportResrc(rid, currentValue)

ok function MqttNode:_readResrc(chk, oid, iid, rid, callback)
ok function MqttNode:_timeoutCtrl(key, delay)
