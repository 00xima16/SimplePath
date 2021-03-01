local PathfindingService = game:GetService("PathfindingService")
local ObjectsHandler = script:WaitForChild("ObjectHandler")
local Objects = require(ObjectsHandler).Objects
local RunService = game:GetService("RunService")

local Path = {}
Path.__index = Path

local function move(self)
	if self.Waypoints[self.currentWaypoint] and self.Running and (self.Waypoints[self.currentWaypoint].Position - self.HumanoidRootPart.Position).Magnitude > 4 then
		self.Moving = true
		self.Humanoid:MoveTo(self.Waypoints[self.currentWaypoint].Position)
		self.elapsed = tick()
	elseif self.Waypoints[self.currentWaypoint] and self.Running and self.currentWaypoint < #self.Waypoints and self.Running then
		self.currentWaypoint += 1
		move(self)
		if self.waypointsFolder then
			self.waypointsFolder[self.currentWaypoint - 1].BrickColor = BrickColor.new("Bright green")
		end
	elseif self.Running then
		self:Stop("Error: Invalid Waypoints")
	end
end

local function onWaypointReached(self, reached)
	if reached and self.currentWaypoint < #self.Waypoints and self.Running then
		self.currentWaypoint += 1
		move(self)
		if self.waypointsFolder then
			self.waypointsFolder[self.currentWaypoint - 1].BrickColor = BrickColor.new("Bright green")
		end	
	elseif self.Running then
		self:Stop("Success: Path Reached")
	end
end

local function timeoutLoop(self)
	while self.Running do
		if self.elapsed and (tick() - self.elapsed) >= self.Timeout and self.Running then
			self:Stop("Error: MoveTo Timeout")
			if self.runOnTimeout then
				self.Humanoid.Jump = true
				self:Run(self.finalPosition, self.showWaypoints, true)
			end
		end
	RunService.Heartbeat:Wait() end
end

local function validate(self)
	local exists = nil
	if #Objects > 0 then
		for i = 1, #Objects do
			if Objects[i][1] == nil or Objects[i][1].Parent == nil then
				table.remove(Objects, i)
				validate(self)
				break
			end
			if Objects[i] and Objects[i][1] == self.Rig then
				exists = Objects[i][2]
				break
			end
		end
	end
	if not exists then
		table.insert(Objects, #Objects + 1, {self.Rig, self})
		exists = self
	else
		self = nil
	end
	return exists
end

local function removeObject(self)
	for i = 1, #Objects do
		if Objects[i][1] == self.Rig then
			table.remove(Objects, i)
			break
		end
	end
end

function Path.new(Rig, PathParams, StorePath)
	
	local self = setmetatable({}, Path)
	
	self.Rig = Rig
	self.HumanoidRootPart = Rig:WaitForChild("HumanoidRootPart")
	self.Humanoid = Rig:WaitForChild("Humanoid")
	self.Timeout = 1
	
	self.__Blocked = Instance.new("BindableEvent")
	self.__WaypointReached = Instance.new("BindableEvent")
	self.__Completed = Instance.new("BindableEvent")
	self.Blocked = self.__Blocked.Event
	self.WaypointReached = self.__WaypointReached.Event
	self.Completed = self.__Completed.Event
	
	if PathParams then
		self.Path = PathfindingService:CreatePath(PathParams)
	else
		self.Path = PathfindingService:CreatePath()
	end
	
	if game:FindFirstChild("NetworkServer") ~= nil and self.Rig:IsDescendantOf(workspace) then
		self.HumanoidRootPart:SetNetworkOwner(nil)
	end
	
	if StorePath == nil or StorePath then
		return validate(self, Rig)
	else
		return self
	end
end

function Path:Stop(Status)
	self.Running = nil
	self.elapsed = nil
	if self.connection and self.connection.Connected then
		self.connection:Disconnect()
	end
	if self.blockedConnection and self.blockedConnection.Connected then
		self.blockedConnection:Disconnect()
	end
	self.blockedConnection = nil
	self.connection = nil
	if self.waypointsFolder then
		self.waypointsFolder:Destroy()
		self.waypointsFolder = nil
	end
	self.__Completed:Fire(Status, self.Rig, self.finalPosition)
	return
end

function Path:Run(finalPosition, showWaypoints, runOnTimout)
	if self.busy then return end
	self.busy = true
	
	if self.Running then self:Stop("Stopped Previous Path") end
	self.Running = true
	
	self.finalPosition = finalPosition
	local Success, _ = pcall(function()
		self.Path:ComputeAsync(self.InitialPosition or self.HumanoidRootPart.Position, finalPosition)
	end)
	if self.Path.Status == Enum.PathStatus.NoPath or not Success then self:Stop("Error: No path found") self.busy = false return end
	self.Waypoints = self.Path:GetWaypoints()
	
	self.currentWaypoint = 1
	self.runOnTimeout = runOnTimout
	self.showWaypoints = showWaypoints
	
	self.connection = self.Humanoid.MoveToFinished:Connect(function(Reached)
		self.Moving = nil
		self.__WaypointReached:Fire(Reached, self.currentWaypoint, self.Waypoints)
		onWaypointReached(self, Reached)
	end)
	coroutine.wrap(timeoutLoop)(self)
	
	self.blockedConnection = self.Path.Blocked:Connect(function(BlockedWaypoint)
		self.Moving = nil
		self.__Blocked:Fire(BlockedWaypoint, self.currentWaypoint, self.Waypoints)
	end)
	
	pcall(function()
		self.HumanoidRootPart:SetNetworkOwner(nil)
	end)
	
	if self.showWaypoints then
		self.waypointsFolder = Instance.new("Folder", workspace)
		for index, waypoint in ipairs(self.Waypoints) do
			local part = Instance.new("Part")
			part.Name = tostring(index)
			part.Size = Vector3.new(1, 1, 1)
			part.Position = waypoint.Position
			part.Anchored = true
			part.CanCollide = false
			part.Parent = self.waypointsFolder
			part.Material = Enum.Material.Neon
			part.BrickColor = BrickColor.new("Neon orange")
		end
	end
	
	move(self)
	
	self.busy = false
	
end

function Path:Distance(Target)
	local position = Target
	if typeof(Target) == "Instance" then
		position = Target.Position
	end
	return (position - self.HumanoidRootPart.Position).Magnitude
end

function Path:Destroy()
	removeObject(self)
	self = nil
end

return Path
