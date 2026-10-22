-- Poses characters by hand: the riders' sitting and crouching, the hops, the hobby-horse gallop, the
-- umbrella held overhead, Struggle's bat swing. On every body the game sees (owner: "Bots are STILL
-- ruberbanding and floating."): R6 bodies turn at Motor6Ds, but this place's servers build R15 bodies
-- with an AnimationConstraint at each joint instead (every bot's; players' R15 avatars come from the
-- same Roblox builder), and the six modes that posed riders only looked for Motor6Ds: on those bodies
-- they found no joint at all and no limb moved, so riders stood stiff in their sleds, carts, horses
-- and boards, and fallers never held their umbrellas. A joint here is either kind, found by its name
-- ("RightShoulder", R6's "Right Shoulder", ...).
--
-- How a pose shows (measured on a test server, on the bodies Players:CreateHumanoidModelFromDescription
-- builds there): an AnimationConstraint takes a Transform between its two attachments just as a
-- Motor6D takes one between C0 and C1 (part1 = part0 * attachment0 * Transform * attachment1:Inverse()),
-- and the bodies come with IsKinematic on, which keeps the whole body one assembly like Motor6Ds do, so
-- the Transform is where the limb goes (with IsKinematic off a limb is its own assembly, pushed toward
-- it by forces; nothing here changes it). While the Animator plays a track it writes the Transform of
-- the joints it moves every frame, before PreSimulation, over whatever was there, so a pose is written
-- in PreSimulation (Pose.Step), after it: Set and Ease replace it, TurnOver adds to it (a walk's bob
-- stays). Release hands a joint back to the Animator.

local RunService = game:GetService("RunService")

local Pose = {}

-- A joint a pose turns. Base is the joint's own axes in its first part (a Motor6D's C0, an
-- AnimationConstraint's first attachment), so a turn given in that part's axes lands the same on any
-- rig; Written is what the pose last wrote, Under what the Animator had under the last TurnOver.
export type Joint = { Instance: Instance, Base: CFrame, Written: CFrame?, Under: CFrame? }

-- Where each joint is: R15's in the part it moves, R6's in the Torso (its root in the
-- HumanoidRootPart). "Neck" is R15's: R6's has the same name but other axes, so a pose written for
-- R15 must not turn it (ask for it with its part, "Torso").
local HOMES: { [string]: string } = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm",
	RightElbow = "RightLowerArm",
	LeftWrist = "LeftHand",
	RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot",
	RightAnkle = "RightFoot",
	RootJoint = "HumanoidRootPart",
	["Left Shoulder"] = "Torso",
	["Right Shoulder"] = "Torso",
	["Left Hip"] = "Torso",
	["Right Hip"] = "Torso",
}

-- A character's joint by name, a Motor6D or an AnimationConstraint (nil if the body has none), in
-- the part it's always in (or in `partName`).
function Pose.Joint(character: Model, name: string, partName: string?): Joint?
	local home = partName or HOMES[name]
	local part = home and character:FindFirstChild(home)
	local found = part and part:FindFirstChild(name)
	if found and found:IsA("Motor6D") then
		return { Instance = found, Base = found.C0.Rotation }
	elseif found and found:IsA("AnimationConstraint") then
		local attachment = found.Attachment0
		return { Instance = found, Base = if attachment then attachment.CFrame.Rotation else CFrame.identity }
	end
	return nil
end

-- The joints named in `names` that a character has, by name.
function Pose.Rig(character: Model, names: { string }): { [string]: Joint }
	local rig = {}
	for _, name in names do
		rig[name] = Pose.Joint(character, name)
	end
	return rig
end

-- Sets a joint's Transform (between C0 and C1, or between the attachments), instead of the Animator's:
-- what Motor6D.Transform always was, so a pose written for Motor6Ds shows the same on either kind.
function Pose.Set(joint: Joint, transform: CFrame)
	(joint.Instance :: any).Transform = transform
	joint.Written = transform
end

-- Eases a joint from what the pose last wrote (the rest pose at first) toward `target`.
function Pose.Ease(joint: Joint, target: CFrame, alpha: number)
	Pose.Set(joint, (joint.Written or CFrame.identity):Lerp(target, alpha))
end

-- Turns a joint by `rotation` given in its first part's axes, about the joint, instead of the Animator.
function Pose.Turn(joint: Joint, rotation: CFrame)
	Pose.Set(joint, joint.Base:Inverse() * rotation * joint.Base)
end

-- What TurnOver writes: `rotation` (in the first part's axes) on top of `under`, the Animator's pose.
function Pose.Over(under: CFrame, base: CFrame, rotation: CFrame): CFrame
	return under * base:Inverse() * rotation * base
end

-- The Animator's pose under a joint now: its Transform, unless that's still what the pose last wrote
-- (nothing wrote it since), when the Animator's last one is used again, so turns never pile up.
function Pose.Under(current: CFrame, written: CFrame?, under: CFrame?): CFrame
	if written and current:FuzzyEq(written, 1e-5) then
		return under or CFrame.identity
	end
	return current
end

-- Turns a joint on top of what the Animator gave it this frame (a walk's bob stays).
function Pose.TurnOver(joint: Joint, rotation: CFrame)
	local under = Pose.Under((joint.Instance :: any).Transform, joint.Written, joint.Under)
	joint.Under = under
	Pose.Set(joint, Pose.Over(under, joint.Base, rotation))
end

-- Hands a joint back to the Animator: as it was under the pose (at rest when the pose replaced it).
function Pose.Release(joint: Joint?)
	if joint and joint.Written then
		pcall(function()
			(joint.Instance :: any).Transform = joint.Under or CFrame.identity
		end)
		joint.Written, joint.Under = nil, nil
	end
end

-- Hands every joint of a rig back.
function Pose.ReleaseAll(rig: { [any]: Joint })
	for _, joint in rig do
		Pose.Release(joint)
	end
end

-- Runs `step(dt)` every frame just before physics, after the Animator has written its pose, so the
-- pose written here is the one that shows (PreSimulation; Stepped where there's none).
function Pose.Step(step: (dt: number) -> ()): RBXScriptConnection
	local pre = (RunService :: any).PreSimulation
	if pre then
		return pre:Connect(step)
	end
	return RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
end

return Pose
