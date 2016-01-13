local a=require'events'local b=require'mqcore'local M=a:new()local c=60000;function M:new(d)d=d or{}assert(type(d.mac)=='string',"mac should be a string.")assert(type(d.ip)=='string',"ip should be a string.")
d.clientId=d.clientId or'qn-'..d.mac;d.lifetime=d.lifetime or 86400;d.version=d.version or'0.0.1'd.mc=nil;d.so=nil;d._tid=0;d._repAttrs={}d._tobjs={}d._lfsecs=0;d._upder=nil;self.__index=self;
d=setmetatable(d,self)b.register(d)return d end;function M:encrypt(e)return e end;function M:decrypt(e)return e end;function M:changeIp(ip)if ip~=self.ip then self.ip=ip;self.so[4][4]=self.ip;
self:pubUpdate({ip=self.ip})end end;function M:initResrc(...)local f,g,h=...f=tonumber(f)or f;g=tonumber(g)or g;self.so[f]=self.so[f]or{}self.so[f][g]=self.so[f][g]or{}for i,j in pairs(h)do 
if type(j)~='function'then self.so[f][g][i]=j;if type(j)=='table'then j._isCb=type(j.read)=='function'or type(j.write)=='function'or type(j.exec)=='function'end end end;return self end;
function M:getAttrs(...)local f,g,i=...local k,l,m,n=self:_target(...),tostring(f)local o={pmin=self.so[1][2],pmax=self.so[1][3],mute=true,cancel=true}if l==tag.notfound then return nil end;
if k==trgtype.object then m=m elseif k==trgtype.instance then m=m..':'..tostring(g)elseif k==trgtype.resource then m=m..':'..tostring(g)..':'..tostring(i)end;self._repAttrs[m]=self._repAttrs[m]or o;
return self._repAttrs[m]end;function M:setAttrs(...)local p={...}local f,m=p[1],tostring(p[1])local g,i,k,l,n;if#p==4 then g,i,n=p[2],p[3],p[4]m=m..':'..tostring(g)..':'..tostring(i)
elseif#p==3 then g,n=p[2],p[3]m=m..':'..tostring(g)elseif#p==2 then n=p[2]end;k,l=self:_target(f,g,i)if l==tag.notfound then return false end;
n.pmin=n.pmin or self.so[1][2]n.pmax=n.pmax or self.so[1][3]self._repAttrs[m]=n;return true end;function M:readResrc(f,g,i,q)return self:_rd(true,f,g,i,q)end;
function M:writeResrc(f,g,i,r,q)local s;f=tonumber(f)or f;i=tonumber(i)or i;q=q or function(...)end;if self:_has(f,g,i)then local t=self.so[f][g][i]local u=type(t)if u=='table'then if t._isCb 
then if type(t.write)=='function'then pcall(t.write,r,function(v,w)s=w;q(v,w)end)else q(b.ERR.unwt,nil)end else self.so[f][g][i]=r;s=r;q(b.ERR.sces,r)end elseif u=='function'or u=='thread'
then q(b.ERR.unwt,nil)else self.so[f][g][i]=r;s=r;q(b.ERR.sces,r)end else q(b.ERR.nfnd,nil)end;if s~=nil then self:_chkResrc(f,g,i,s)end end;function M:execResrc(f,g,i,x,q)q=q or function(...)end;
f=tonumber(f)or f;i=tonumber(i)or i;if self:_has(f,g,i)then local t=self.so[f][g][i]if type(t)~='table'or type(t.exec)~='function'then q(b.ERR.une,{status=b.RSP.nalw})else pcall(t.exec,x,q)end 
else q(b.ERR.nfnd,{status=b.RSP.nfnd})end end;function M:connect(y,z)z=z or{}z.port=z.port or 1883;z.secure=z.secure or 0;if self.mc==nil then self.mc=mqtt.Client(self.clientId,z.keepalive or 120,
z.username or'freebird',z.password or'skynyrd',z.cleansession or 1)end;self.mc:connect(y,z.port,z.secure,function(A)self.mc:on('message',function(B,C,e)self:emit('raw',B,C,e)end)end)end;
function M:close(q)if self.mc~=nil then self.mc:close()end;if q~=nil then q()end end;function M:pubRegister(q)local data={transId=nil,lifetime=self.lifetime,objList={},ip=self.ip,mac=self.mac,
version=self.version}for f,D in pairs(self.so)do for g,E in pairs(D)do table.insert(data.objList,{oid=f,iid=g})end end;return self:_pubReq('register',data)end;
function M:pubDeregister(q)return self:_pubReq('deregister',{data=nil})end;function M:pubNotify(data,q)return self:_pubReq('notify',data,function(v,F)if F.cancel then 
self:disableReport(data.oid,data.iid,data.rid)end;if q~=nil then q(v,F)end end)end;function M:pingServer(q)return self:_pubReq('ping',{data=nil})end;function M:pubUpdate(G,q)return self:_pubReq('update',G)end;
function M:pubResponse(F,q)return self:publish(self._pubics.response,F,q)end;function M:publish(C,H,I,q)if type(I)=='function'then q=I;I=nil end;local J,K,L=I.qos or 0,I.retain or 0,H;
if type(H)=='table'then H=cjson.encode(H)end;self.mc:publish(C,self:encrypt(H),J,K,function(B)self:emit('published',{topic=C,message=L,options=I})if q~=nil then q()end end)end;
function M:subscribe(C,J,q)if type(J)=='function'then q=J;J=nil end;self.mc:subscribe(C,J or 0,q)end;function M:_pubReq(N,data,q)data.transId=self:_id(N)if q~=nil then 
local m=N..':rsp:'..tostring(data.transId)self._tCtrl(m,c)self:once(m,q)end;return self:publish(self._pubics[N],data)end;function M:_target(f,g,i)local k,l;if f~=nil and f==''then k=trgtype.root 
elseif f~=nil then k=trgtype.object;if g~=nil then k=trgtype.instance;if i~=nil then k=trgtype.resource end end end;if k==trgtype.object then l=self:_dumpObj(f)elseif k==trgtype.instance 
then l=self:_dumpObj(f,g)elseif k==trgtype.resource then self:_rd(false,f,g,i,function(v,w)l=w end)end;if l==nil then l=tag.notfound end;return k,l end;
function M:_id(N)local O=function()self._tid=self._tid+1;if self._tid>255 then self._tid=0 end end;if N~=nil then local P=N..':rsp:'..tostring(self._tid)while self:listenerCount(P)~=0 do P=N..':rsp:'..tostring(O())end end;
return self._tid end;function M:_dumpObj(...)local f,g=...local Q,D={},self.so[f]if D==nil then Q=nil elseif g==nil then for R,S in pairs(D)do Q[R]={}for i,t in pairs(D[R])
do self:readResrc(f,R,i,function(v,w)Q[R][i]=w end)end end else if D[g]==nil then Q=nil else for i,t in pairs(D[g])do self:readResrc(f,g,i,function(v,w)Q[i]=w end)end end end;return Q end;
function M:_rd(T,f,g,i,q)local s;f=tonumber(f)or f;i=tonumber(i)or i;q=q or function(...)end;if self:_has(f,g,i)then local t=self.so[f][g][i]local u=type(t)if u=='table'and t._isCb==true 
then if type(t.read)=='function'then pcall(t.read,function(v,w)s=w;q(v,w)end)elseif type(t.exec)=='function'then q(b.ERR.unrd,tag.exec)else q(b.ERR.unrd,b.TAG.unrd)end 
elseif u=='function'or u=='thread'then q(b.ERR.unrd,nil)else s=t;q(b.ERR.sces,t)end else q(b.ERR.nfnd,nil)end;if T==true and s~=nil then self:_chkResrc(f,g,i,s)end end;
function M:_has(f,g,i)return self.so[f]~=nil and self.so[f][g]~=nil and self.so[f][g][i]~=nil end;return M