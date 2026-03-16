-- Handles weapon recoil and bullet spread for the client.
-- Recoil has two layers: "kick" (snappy, per-shot punch) and "drift" (slower camera pull that accumulates).
-- Both decay over time, and the camera smoothly interpolates toward the combined offset each frame.

local RecoilClient = {}

local DEFAULT_SPREAD = 0.15
local MOVE_SPEED_CLAMP = 2
local DRIFT_SPREAD_MUL = 0.15   -- how much accumulated drift widens your crosshair
local SMOOTH_RATE_MUL = 22      -- higher = camera snaps to recoil target faster
local DRIFT_DECAY_RATE = 15     -- how fast consecutive shot count drains when idle

export type AccuracyConfig = {
	BaseSpread: number,         -- resting crosshair size in degrees
	SprintMul: number?,         -- spread multiplier while sprinting (default 2.5)
	MoveSpread: number?,        -- additive spread per unit of movement speed (default 1.2)
	CrouchMul: number?,         -- spread multiplier while crouching (default 0.6, tighter)
	AimSpreadMul: number?,      -- spread multiplier while aiming down sights (default 0.05, very tight)
}

export type RecoilConfig = {
	KickPitch: number,          -- upward camera punch per shot (degrees)
	KickYawRange: number,       -- max horizontal camera punch, randomized left/right
	DriftPitch: number,         -- sustained upward pull added per shot
	DriftYawRange: number,      -- sustained horizontal pull, randomized per shot
	Buildup: number?,           -- extra recoil added per consecutive shot (default 0.012)
	FirstShotMul: number?,      -- multiplier on the very first shot, usually lower for accuracy (default 0.35)
	MaxDrift: number?,          -- ceiling for accumulated drift so it does not climb forever (default 1.6)
	KickDecay: number?,         -- how fast kick fades each frame (default 18)
	RecoverySpeed: number?,     -- how fast drift fades after you stop shooting (default 10)
	RecoverDelay: number?,      -- grace period before drift starts recovering (default 0.04s)
}

export type RecoilState = {
	kickPitch: number,          -- current kick offset (vertical)
	kickYaw: number,            -- current kick offset (horizontal)
	driftPitch: number,         -- accumulated drift (vertical)
	driftYaw: number,           -- accumulated drift (horizontal)
	smoothPitch: number,        -- interpolated pitch the camera is moving toward
	smoothYaw: number,          -- interpolated yaw the camera is moving toward
	appliedPitch: number,       -- pitch already applied to the camera last frame
	appliedYaw: number,         -- yaw already applied to the camera last frame
	consecutiveShots: number,   -- running count of shots in this burst
	lastShotTime: number,       -- timestamp of the most recent shot
}

-- Fresh state with everything zeroed out. Call this once per weapon equip.
function RecoilClient.createState(): RecoilState
	return {
		kickPitch = 0,
		kickYaw = 0,
		driftPitch = 0,
		driftYaw = 0,
		smoothPitch = 0,
		smoothYaw = 0,
		appliedPitch = 0,
		appliedYaw = 0,
		consecutiveShots = 0,
		lastShotTime = 0,
	}
end

-- Calculates the current bullet spread in degrees based on movement, stance, and drift.
-- Sprinting and moving widen the cone. Crouching and aiming tighten it.
-- Accumulated drift also feeds back into spread so sustained fire gets less accurate.
function RecoilClient.getSpread(accuracy: AccuracyConfig?, moveState: any, walkSpeed: number, hSpeed: number, driftPitch: number, aiming: boolean): number
	if not accuracy then return DEFAULT_SPREAD end

	local spread = accuracy.BaseSpread

	if moveState.sprinting then
		spread *= accuracy.SprintMul or 2.5
	elseif hSpeed > 1 then
		-- scale additive spread by how fast you are moving relative to walk speed
		spread += (accuracy.MoveSpread or 1.2) * math.clamp(hSpeed / walkSpeed, 0, MOVE_SPEED_CLAMP)
	end

	if moveState.crouching and not moveState.sliding then
		spread *= accuracy.CrouchMul or 0.6
	end

	if aiming then
		spread *= accuracy.AimSpreadMul or 0.05
	end

	-- sustained fire gradually blooms the crosshair through drift
	spread += driftPitch * DRIFT_SPREAD_MUL

	return spread
end

-- Rotates a direction vector by a random angle within the spread cone.
-- Uses spherical offset: random azimuth (phi) around the axis, random polar angle (theta) within the cone.
function RecoilClient.applySpread(direction: Vector3, spread: number): Vector3
	local spreadRad = math.rad(spread)
	local phi = math.random() * math.pi * 2     -- full circle around the aim direction
	local theta = math.random() * spreadRad      -- random deflection up to the spread limit
	return (CFrame.new(Vector3.zero, direction) * CFrame.Angles(0, 0, phi) * CFrame.Angles(theta, 0, 0)).LookVector
end

-- Fires one shot worth of recoil into the state.
-- The first shot in a burst is softer (FirstShotMul). Each consecutive shot adds a bit more (Buildup).
-- Kick is the instant punch. Drift is the slower pull that stacks up to MaxDrift.
function RecoilClient.applyKick(recoilCfg: RecoilConfig, state: RecoilState, noRecoil: boolean)
	if noRecoil then return end

	local shotMul = state.consecutiveShots == 1 and (recoilCfg.FirstShotMul or 0.35) or 1
	local builtup = (recoilCfg.Buildup or 0.012) * math.min(state.consecutiveShots, 25)

	-- kick: fast, decays quickly
	state.kickPitch += (recoilCfg.KickPitch + builtup) * shotMul
	state.kickYaw += (math.random() - 0.5) * 2 * recoilCfg.KickYawRange * shotMul

	-- drift: slow, accumulates, capped at MaxDrift
	state.driftPitch = math.min(state.driftPitch + (recoilCfg.DriftPitch + builtup * 0.5) * shotMul, recoilCfg.MaxDrift or 1.6)
	state.driftYaw = math.clamp(
		state.driftYaw + (math.random() - 0.5) * 2 * recoilCfg.DriftYawRange,
		-(recoilCfg.MaxDrift or 1.6) * 0.5, (recoilCfg.MaxDrift or 1.6) * 0.5
	)
end

-- Called every frame. Decays the kick, smooths the camera toward the combined recoil target,
-- and returns the delta (change since last frame) to apply to the camera angles.
function RecoilClient.updateRecoil(state: RecoilState, recoilCfg: RecoilConfig, dt: number)
	-- kick fades fast each frame
	local kickFade = math.min(dt * (recoilCfg.KickDecay or 18), 1)
	state.kickPitch *= (1 - kickFade)
	state.kickYaw *= (1 - kickFade)

	-- the camera target is kick + drift combined
	local targetPitch = state.kickPitch + state.driftPitch
	local targetYaw = state.kickYaw + state.driftYaw

	-- smooth interpolation so the camera does not teleport
	local smoothRate = math.min(dt * SMOOTH_RATE_MUL, 1)
	state.smoothPitch += (targetPitch - state.smoothPitch) * smoothRate
	state.smoothYaw += (targetYaw - state.smoothYaw) * smoothRate

	-- delta is only the portion not yet applied, so the camera moves incrementally
	local deltaPitch = state.smoothPitch - state.appliedPitch
	local deltaYaw = state.smoothYaw - state.appliedYaw
	state.appliedPitch = state.smoothPitch
	state.appliedYaw = state.smoothYaw

	return deltaPitch, deltaYaw
end

-- Called every frame after updateRecoil. Fades the drift back to zero once you stop shooting.
-- A short delay (RecoverDelay) prevents recovery from starting mid-burst.
-- The consecutive shot counter also drains here so buildup resets between bursts.
function RecoilClient.decayDrift(state: RecoilState, recoilCfg: RecoilConfig, dt: number, timeSinceShot: number)
	if timeSinceShot <= (recoilCfg.RecoverDelay or 0.04) then return end

	local fade = math.min(dt * (recoilCfg.RecoverySpeed or 10), 1)
	state.driftPitch *= (1 - fade)
	state.driftYaw *= (1 - fade)

	-- after a longer pause, start draining the shot counter so buildup resets
	if timeSinceShot > 0.25 then
		state.consecutiveShots = math.max(0, state.consecutiveShots - math.ceil(dt * DRIFT_DECAY_RATE))
	end
end

return RecoilClient
