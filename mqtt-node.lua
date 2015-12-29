------------------------------------------------------------------------------
-- Client Device of Light-weight MQTT Machine Network (LWMQN) for NODEMCU
-- LWMQN Project
-- LICENCE: MIT
-- Simen Li <simenkid@gmail.com>
------------------------------------------------------------------------------

local moduleName = ...
local MqttNode = {}
_G[moduleName] = M


function MqttNode:new(o, clientId, devAttrs)
    devAttrs = devAttrs or {}
    self.clientId = clientId
    self.lifetime = devAttrs.lifetime or 86400
    self.ip = devAttrs.ip or nil
    self.mac = devAttrs.mac or nil
    self.version = devAttrs.version or '0.0.1'

    self.mc = nil
    self.so = nil

    self._pubics = {
        register = 'register/' .. self.clientId,
        deregister = 'deregister/' .. self.clientId,
        notify = 'notify/' .. self.clientId,
        update = 'update/' .. self.clientId,
        ping = 'ping/' .. self.clientId,
        response = 'response/' .. self.clientId
    }

    self._subics = {
        register = 'register/response/' .. self.clientId,
        deregister = 'deregister/response/' .. self.clientId,
        notify = 'notify/response/' .. self.clientId,
        update = 'update/response/' .. self.clientId,
        ping = 'ping/response/' .. self.clientId,
        request = 'request/' .. self.clientId,
        announce = 'announce'
    };

end

function MqttNode:encrypt(msg)
    return msg
end

function MqttNode:decrypt(msg)
    return msg
end


function MqttNode:setDevAttrs(devAttrs)

end

function MqttNode:initResrc(oid, iid, resrc)

end

function MqttNode:readResrc(oid, iid, rid, callback)

end

function MqttNode:writeResrc(oid, iid, rid, value, callback)

end

function MqttNode:connect(url, opts)

end

function MqttNode:close()

end

function MqttNode:pubRegister()

end

function MqttNode:pubDeregister()

end

function MqttNode:pubNotify()

end

function MqttNode:pingServer()

end

function MqttNode:publish()

end

function MqttNode:subscribe()

end

function MqttNode:unsubscribe()

end
return MqttNode
--[[
APIs

new MqttNode
setDevAttrs
initResrc
readResrc
writeResrc

connect
close

pubRegister
pubDeregister
pubNotify
pingServer

publish
subscribe
unsubscribe
--]]

