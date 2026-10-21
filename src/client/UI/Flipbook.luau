-- Plays a mini-game's preview (Shared/GamePreviews) on an ImageLabel as a flipbook: the preview is
-- one sprite sheet, and each step shows the next frame of it by moving ImageRectOffset. Cheap: the
-- image loads once and nothing is created per frame. Made for the vote stage's portals (owner:
-- "maybe we make the portal do a little video of what the game actually is?").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePreviews = require(ReplicatedStorage.Shared.GamePreviews)

local Flipbook = {}
Flipbook.__index = Flipbook

export type Flipbook = typeof(setmetatable(
	{} :: {
		Label: ImageLabel,
		Preview: GamePreviews.Preview?,
		Clock: number,
		Frame: number,
	},
	Flipbook
))

function Flipbook.new(label: ImageLabel): Flipbook
	label.Image = ""
	label.ScaleType = Enum.ScaleType.Stretch
	return setmetatable({ Label = label, Preview = nil, Clock = 0, Frame = 0 }, Flipbook)
end

-- The preview for a game id, if it has one.
function Flipbook.PreviewOf(gameId: string?): GamePreviews.Preview?
	return if gameId then (GamePreviews :: any)[gameId] else nil
end

-- Shows this preview from frame 1 (or nothing, for nil). `clock` starts it part-way through, so
-- several screens showing the same game don't play in lockstep.
function Flipbook.Show(self: Flipbook, preview: GamePreviews.Preview?, clock: number?)
	self.Preview = preview
	self.Clock = clock or 0
	self.Frame = 0
	self.Label.Image = if preview then preview.Image else ""
	self.Label.Visible = preview ~= nil
	if preview then
		self.Label.ImageRectSize = preview.FrameSize
		self:Step(0)
	end
end

function Flipbook.SetFrame(self: Flipbook, frame: number)
	local preview = self.Preview
	if not preview or frame == self.Frame then
		return
	end
	self.Frame = frame
	local column = (frame - 1) % preview.Columns
	local row = (frame - 1) // preview.Columns
	self.Label.ImageRectOffset = Vector2.new(column * preview.FrameSize.X, row * preview.FrameSize.Y)
end

-- Moves the flipbook `dt` seconds on (0 just redraws). Speed 0 holds the current frame.
function Flipbook.Step(self: Flipbook, dt: number, speed: number?)
	local preview = self.Preview
	if not preview then
		return
	end
	self.Clock += dt * (speed or 1)
	local frame = math.floor(self.Clock * preview.Fps) % preview.Frames + 1
	self:SetFrame(frame)
end

-- Whether the sheet has loaded (until then, and if it never does, the card under it shows).
function Flipbook.IsLoaded(self: Flipbook): boolean
	return self.Preview ~= nil and self.Label.IsLoaded
end

return Flipbook
