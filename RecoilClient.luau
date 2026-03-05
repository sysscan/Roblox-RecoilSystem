local RecoilClient = {}

local DEFAULT_SPREAD = 0.15
local MOVE_SPEED_CLAMP = 2
local DRIFT_SPREAD_MUL = 0.15
local SMOOTH_RATE_MUL = 22
local DRIFT_DECAY_RATE = 15

export type AccuracyConfig = {
	BaseSpread: number,
	SprintMul: number?,
	MoveSpread: number?,
	CrouchMul: number?,
	AimSpreadMul: number?,
}

export type RecoilConfig = {
	KickPitch: number,
	KickYawRange: number,
	DriftPitch: number,
	DriftYawRange: number,
	Buildup: number?,
	FirstShotMul: number?,
	MaxDrift: number?,
	KickDecay: number?,
	RecoverySpeed: number?,
	RecoverDelay: number?,
}

export type RecoilState = {
	kickPitch: number,
	kickYaw: number,
	driftPitch: number,
	driftYaw: number,
	smoothPitch: number,
	smoothYaw: number,
	appliedPitch: number,
	appliedYaw: number,
	consecutiveShots: number,
	lastShotTime: number,
}

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

function RecoilClient.getSpread(accuracy: AccuracyConfig?, moveState: any, walkSpeed: number, hSpeed: number, driftPitch: number, aiming: boolean): number
	if not accuracy then return DEFAULT_SPREAD end
	local spread = accuracy.BaseSpread
	if moveState.sprinting then
		spread *= accuracy.SprintMul or 2.5
	elseif hSpeed > 1 then
		spread += (accuracy.MoveSpread or 1.2) * math.clamp(hSpeed / walkSpeed, 0, MOVE_SPEED_CLAMP)
	end
	if moveState.crouching and not moveState.sliding then
		spread *= accuracy.CrouchMul or 0.6
	end
	if aiming then
		spread *= accuracy.AimSpreadMul or 0.05
	end
	spread += driftPitch * DRIFT_SPREAD_MUL
	return spread
end

function RecoilClient.applySpread(direction: Vector3, spread: number): Vector3
	local spreadRad = math.rad(spread)
	local phi = math.random() * math.pi * 2
	local theta = math.random() * spreadRad
	return (CFrame.new(Vector3.zero, direction) * CFrame.Angles(0, 0, phi) * CFrame.Angles(theta, 0, 0)).LookVector
end

function RecoilClient.applyKick(recoilCfg: RecoilConfig, state: RecoilState, noRecoil: boolean)
	if noRecoil then return end
	local shotMul = state.consecutiveShots == 1 and (recoilCfg.FirstShotMul or 0.35) or 1
	local builtup = (recoilCfg.Buildup or 0.012) * math.min(state.consecutiveShots, 25)
	state.kickPitch += (recoilCfg.KickPitch + builtup) * shotMul
	state.kickYaw += (math.random() - 0.5) * 2 * recoilCfg.KickYawRange * shotMul
	state.driftPitch = math.min(state.driftPitch + (recoilCfg.DriftPitch + builtup * 0.5) * shotMul, recoilCfg.MaxDrift or 1.6)
	state.driftYaw = math.clamp(
		state.driftYaw + (math.random() - 0.5) * 2 * recoilCfg.DriftYawRange,
		-(recoilCfg.MaxDrift or 1.6) * 0.5, (recoilCfg.MaxDrift or 1.6) * 0.5
	)
end

function RecoilClient.updateRecoil(state: RecoilState, recoilCfg: RecoilConfig, dt: number)
	local kickFade = math.min(dt * (recoilCfg.KickDecay or 18), 1)
	state.kickPitch *= (1 - kickFade)
	state.kickYaw *= (1 - kickFade)
	local targetPitch = state.kickPitch + state.driftPitch
	local targetYaw = state.kickYaw + state.driftYaw
	local smoothRate = math.min(dt * SMOOTH_RATE_MUL, 1)
	state.smoothPitch += (targetPitch - state.smoothPitch) * smoothRate
	state.smoothYaw += (targetYaw - state.smoothYaw) * smoothRate
	local deltaPitch = state.smoothPitch - state.appliedPitch
	local deltaYaw = state.smoothYaw - state.appliedYaw
	state.appliedPitch = state.smoothPitch
	state.appliedYaw = state.smoothYaw
	return deltaPitch, deltaYaw
end

function RecoilClient.decayDrift(state: RecoilState, recoilCfg: RecoilConfig, dt: number, timeSinceShot: number)
	if timeSinceShot <= (recoilCfg.RecoverDelay or 0.04) then return end
	local fade = math.min(dt * (recoilCfg.RecoverySpeed or 10), 1)
	state.driftPitch *= (1 - fade)
	state.driftYaw *= (1 - fade)
	if timeSinceShot > 0.25 then
		state.consecutiveShots = math.max(0, state.consecutiveShots - math.ceil(dt * DRIFT_DECAY_RATE))
	end
end

return RecoilClient
