# Roblox Recoil System

Config-driven recoil and spread for FPS weapons. Handles kick, drift, buildup, and recovery.

## Installation

Copy `RecoilClient.luau` into your project.

## Usage

```lua
local RecoilClient = require(path.to.RecoilClient)

local recoilState = RecoilClient.createState()
local recoilCfg = {
    KickPitch = 0.3,
    KickYawRange = 0.12,
    DriftPitch = 0.06,
    DriftYawRange = 0.04,
    Buildup = 0.012,
    FirstShotMul = 0.35,
    MaxDrift = 1.6,
    KickDecay = 18,
    RecoverySpeed = 10,
    RecoverDelay = 0.04,
}

local accuracyCfg = {
    BaseSpread = 2.2,
    MoveSpread = 1.2,
    CrouchMul = 0.6,
    SprintMul = 2.5,
    AimSpreadMul = 0.05,
}
```

### On Fire

```lua
recoilState.consecutiveShots += 1
recoilState.lastShotTime = os.clock()
RecoilClient.applyKick(recoilCfg, recoilState, false)
```

### Each Frame

```lua
local deltaPitch, deltaYaw = RecoilClient.updateRecoil(recoilState, recoilCfg, dt)
RecoilClient.decayDrift(recoilState, recoilCfg, dt, os.clock() - recoilState.lastShotTime)
-- Apply deltaPitch, deltaYaw to camera
```

### Spread

```lua
local spread = RecoilClient.getSpread(accuracyCfg, moveState, walkSpeed, hSpeed, recoilState.driftPitch, aiming)
local direction = RecoilClient.applySpread(aimDirection, spread)
```

## License

MIT
