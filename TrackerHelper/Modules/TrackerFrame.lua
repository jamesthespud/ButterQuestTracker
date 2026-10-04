local CreateClass = LibStub("BQTFrameClass-1.0");

TrackerHelperFrame = CreateClass("Frame", "TrackerHelperFrame", nil, nil, TrackerHelperBase);
local Frame = TrackerHelperFrame;

function Frame:OnCreate()
    TrackerHelperBase.OnCreate(self);

    local setWidth = self.SetWidth;
    function self:SetWidth(width)
        setWidth(self, width);
        self.content:RefreshSize();
        -- Re-anchor the frame to prevent sizing issues
        self:SetPosition(self:GetPosition());
    end

    local setHeight = self.SetHeight;
    function self:SetHeight(height)
        if not self.maxHeight then
            setHeight(self, self.content:GetFullHeight());
        else
            setHeight(self, math.min(self.content:GetFullHeight(), self.maxHeight));
        end

        -- Re-anchor the frame to prevent sizing issues
        self:SetPosition(self:GetPosition());
        self:_clampScroll();
    end

    local stopMovingOrSizing = self.StopMovingOrSizing;
    function self:StopMovingOrSizing()
        stopMovingOrSizing(self);
        self:SetUserPlaced(false);
        -- Re-anchor the frame to prevent sizing issues
        self:SetPosition(self:GetPosition());
    end
end

function Frame:OnAcquire()
    self.locked = false;
    self.background = TrackerHelperBackgroundFrame(self);

    self:SetClipsChildren(true);
    self:SetClampedToScreen(true);
    self:SetFrameStrata("BACKGROUND");
    self:SetSize(1, 1);
    self:EnableMouseWheel(true);
    self:SetMovable(true);
    self:SetBackgroundColor({
        r = 0.0,
        g = 0.0,
        b = 0.0,
        a = 0.5
    });
    self:SetPosition(0, 400);

    self:SetBackgroundVisibility(false);
    self:SetLocked(false);

    self:SetScript("OnMouseWheel", self.OnMouseWheel);

    self:Clear();
    self:SetWidth(200);
    self:SetMaxHeight(500);
end

function Frame:Clear()
    if self.content then
        self.content:Release();
    end

    self.elements = {};
    self.content = TrackerHelperContainer(self);
end

-- Element Creators

function Frame:Container(options)
    options = options or {};

    local container = TrackerHelperContainer(options.container or self.content);

    container:SetMargin(options.margin);
    container:SetBackgroundColor(options.backgroundColor);

    if options.events then
        for event, listener in pairs(options.events) do
            container:AddListener(event, listener);
        end
    end

    container:UpdateParentsHeight(container:GetFullHeight());
    container:SetHidden(options.hidden);
    container:SetMetadata(options.metadata);

    return container;
end

function Frame:Font(options)
    options = options or {};

    local font = TrackerHelperFont(options.container or self.content);
    font:SetMargin(options.margin);
    font:SetColor(options.color);
    font:SetHoverColor(options.hoverColor);
    font:SetLabel(options.label);
    font:SetSize(options.size or 12);

    font:UpdateParentsHeight(font:GetFullHeight());

    return font;
end

-- Getters & Setters

function Frame:UpdateSettings(settings)
    if settings.maxHeight ~= nil then
        self:SetMaxHeight(settings.maxHeight);
    end

    if settings.width ~= nil then
        self:SetWidth(settings.width);
    end

    if settings.backgroundColor ~= nil then
        self:SetBackgroundColor(settings.backgroundColor);
    end

    if settings.position ~= nil then
        self:SetPosition(settings.position.x, settings.position.y);
    end

    if settings.backgroundVisible ~= nil then
        self:SetBackgroundVisibility(settings.backgroundVisible);
    end

    if settings.locked ~= nil then
        self:SetLocked(settings.locked);
    end
end

function Frame:SetBackgroundVisibility(visible)
    self.background:SetBackgroundVisibility(visible);
end

function Frame:SetBackgroundColor(backgroundColor)
    self.background:SetBackgroundColor(backgroundColor);
end

-- Offset of our top right corner from UIParent's top right corner (what SetPosition expects).
function Frame:GetPosition()
    local x = self:GetRight();
    local y = self:GetTop();

    local parentRight = UIParent:GetRight() or GetScreenWidth();
    local parentTop = UIParent:GetTop() or GetScreenHeight();

    -- Frames that haven't been laid out yet report nothing, fall back to the last known spot.
    if not (x and y and parentRight and parentTop) then
        if self.position then
            return self.position.x, self.position.y;
        end

        return nil, nil;
    end

    return x - parentRight, y - parentTop;
end

function Frame:SetPosition(x, y)
    local current = self.position or { x = 0, y = 0 };

    if x == nil then
        x = current.x;
    end

    if y == nil then
        y = current.y;
    end

    self:ClearAllPoints();
    self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y);

    self.position = { x = x, y = y };
end

function Frame:SetMaxHeight(maxHeight)
    self.maxHeight = maxHeight;

    self:SetHeight(self:GetHeight());
end

function Frame:SetLocked(locked)
    self.locked = locked;

    if self.content then
        self.content:SetLocked(locked);
    end
end

-- Events

function Frame:OnMouseWheel(value)
    -- The first anchor of the content is always its "TOP" point. (GetPoint wants an index,
    -- passing a point name only ever worked by accident.)
    local _, _, _, _, y = self.content:GetPoint(1);

    self.content:SetPoint("TOP", self, 0, (y or 0) + 10 * -value);

    self:_clampScroll(self.content);
end

-- Helpers

function Frame:_clampScroll()
    local parent = self.content:GetParent();

    local contentTop, contentBottom = self.content:GetTop(), self.content:GetBottom();
    local parentTop, parentBottom = parent:GetTop(), parent:GetBottom();

    -- Nothing to clamp until the frames have been laid out.
    if not (contentTop and contentBottom and parentTop and parentBottom) then return end

    if contentTop < parentTop then
        self.content:SetPoint("TOP", parent, 0, 0);
    elseif contentBottom > parentBottom then
        self.content:SetPoint("TOP", parent, 0, self.content:GetHeight() - parent:GetHeight());
    end
end
