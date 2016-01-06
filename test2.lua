print( nil * 10)

-- local x = 120
-- local x = tonumber(x) or x
-- print(x)
-- print(type(x))

-- local Person = {
--     name = 'simen',
--     gender = 'male',
-- }

-- -- setmetatable(Person, {
-- --     __call = function (_, ...)
-- --         return Person:new(...)
-- --     end
-- -- })

-- function Person:new(o, name)

--     o = o or {}
--     self.__index = self

--     print('Person self: ')
--     print(self)

--     o = setmetatable(o, self)
--     o.name = name

--     o.counter = 0
--     o.count = function ()
--         print(o.counter)
--         o.counter = o.counter + 1
--     end
--     return o
-- end

-- -- function Person:init(name)
-- --     self.name = name
-- -- end

-- function Person:greet(callback)
--     --print(self)
--     print('hi, I am ' .. self.name)

--     if (self.mail) then
--         print('mail: ' .. self.mail)
--     end

--     if (callback) then callback('greeted') end
-- end

-- function Person:identify(callback)
--     local c = 'out'
--     print('#######1')
--     print(self)

--     self.greet({ name= 'hi', mail= 'how' }, function () 
--         print('#######2')
--         print(self)
--         print(c)
--         callback()
--     end)
-- end


-- local psn1 = Person:new({}, 'hedy')

-- psn1.count()
-- psn1.count()
-- psn1.count()
-- psn1.count()
-- psn1.count()
-- psn1.count()
-- print(psn1.counter)
-- -- psn1:identify(function () 
-- --     print('#######3')
-- --     print(self)
-- -- end)
-- -- print('Person class: ')
-- -- print(Person)
-- -- print('Person psn1: ')
-- -- print(psn1)

-- -- -- psn1.name = 'hedy'
-- -- psn1.mail = 'abc.com'
-- -- -- psn1.gender = 'female'
-- -- print('**************')
-- -- Person:identify()
-- -- psn1:identify()

-- -- Person:greet()
-- -- psn1:greet()

-- -- -- print(Person.mail)
-- -- -- print(psn1.mail)