--[[
    BQTFrameClass-1.0

    A tiny, dependency free replacement for Poncho-1.0, which the tracker UI used to
    build its pooled frames. Poncho-1.0 relied on Blizzard's global `UIFrameCache` and on
    the internals of the frame metatable; both are the kind of thing Blizzard removes
    without warning. This version only needs `CreateFrame`.

    API (identical to what the old Poncho calls in this addon used):

        local CreateClass = LibStub("BQTFrameClass-1.0");
        MyClass = CreateClass("Frame", "MyClass", nil, nil, SuperClass);

        function MyClass:OnCreate()  end   -- once, when a brand new frame is built
        function MyClass:OnAcquire() end   -- every time a frame is handed out
        function MyClass:OnRelease() end   -- every time a frame is given back

        local frame = MyClass(parent);     -- get a frame (new or recycled)
        frame:Release();                   -- give it back to the pool

    Class methods are copied onto each frame instance (subclass methods win), so methods
    shadow the built in widget methods exactly like the old metatable approach did.
]]

local MAJOR, MINOR = "BQTFrameClass-1.0", 1;
local Lib = LibStub:NewLibrary(MAJOR, MINOR);
if not Lib then return end

local type, pairs, rawget, setmetatable = type, pairs, rawget, setmetatable;
local tinsert, tremove = table.insert, table.remove;

local function safecall(frame, key)
    local method = frame[key];

    if type(method) == "function" then
        return method(frame);
    end
end

-- The abstract root class every other class eventually inherits from.
local Base = {};
Lib.Base = Base;

function Base:GetFrame(parent)
    local frame = tremove(self.__pool);
    local isNew = false;

    if not frame then
        frame = CreateFrame(self.__frameType, nil, parent or UIParent, self.__template);
        isNew = true;

        -- Copy the methods of the whole class chain, root first so subclasses override.
        local chain, class = {}, self;
        while class do
            tinsert(chain, 1, class);
            class = rawget(class, "__super");
        end

        for _, link in ipairs(chain) do
            for key, value in pairs(link) do
                if type(value) == "function" and type(key) == "string" and key:sub(1, 2) ~= "__" then
                    frame[key] = value;
                end
            end
        end

        frame.__class = self;
    end

    frame.__released = false;

    if isNew then
        safecall(frame, "OnCreate");
    end

    if parent then
        frame:SetParent(parent);
    end

    safecall(frame, "OnAcquire");

    return frame;
end

function Base:ReleaseFrame(frame)
    if frame.__released then return end

    frame.__released = true;
    tinsert(self.__pool, frame);

    safecall(frame, "OnRelease");
end

-- Called on a frame: returns it to its class' pool.
function Base:Release()
    local class = self.__class;

    if class then
        class:ReleaseFrame(self);
    end
end

local classMeta = {
    __index = function(class, key)
        local super = rawget(class, "__super");

        if super then
            return super[key];
        end
    end,

    __call = function(class, ...)
        return class:GetFrame(...);
    end
};

function Lib:NewClass(frameType, name, parent, template, super)
    local class = setmetatable({
        __frameType = frameType or "Frame",
        __name = name,
        __template = template,
        __super = super or Base,
        __pool = {}
    }, classMeta);

    if name then
        _G[name] = class;
    end

    return class;
end

setmetatable(Lib, {
    __call = function(lib, ...)
        return lib:NewClass(...);
    end
});
