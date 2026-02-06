# Quick XP Tracking Test

## Step-by-Step Testing

### 1. Reload and Enable Debug
```
/reload
/goldph debug verbose on
```

### 2. Check Your Level
Make sure you're NOT at max level:
- Classic: Must be < level 60
- TBC: Must be < level 70

### 3. Start a Session
```
/goldph start
```

You should see in chat:
- `[GoldPH] Session #X started`
- `[GoldPH] Initialized reputation cache with X factions` (if verbose on)

### 4. Check Session Structure
Run this in chat (copy/paste):
```lua
/script local s = GoldPH_SessionManager:GetActiveSession(); if s then print("Session exists"); print("metrics: " .. tostring(s.metrics ~= nil)); print("metrics.xp: " .. tostring(s.metrics and s.metrics.xp ~= nil)); print("snapshots: " .. tostring(s.snapshots ~= nil)); print("snapshots.xp: " .. tostring(s.snapshots and s.snapshots.xp ~= nil)); else print("No session"); end
```

Expected output:
```
Session exists
metrics: true
metrics.xp: true
snapshots: true
snapshots.xp: true
```

### 5. Check Current XP
```lua
/script print("Level: " .. UnitLevel("player")); print("XP: " .. UnitXP("player") .. "/" .. UnitXPMax("player")); print("Max: " .. MAX_PLAYER_LEVEL)
```

### 6. Gain Some XP
Kill 3-5 mobs that give XP. You should see in chat:
```
[GoldPH] XP gained: 150 (total: 150)
[GoldPH] XP gained: 150 (total: 300)
...
```

### 7. Check HUD
- Make sure HUD is expanded (click the - button if it's minimized)
- Look for "Metrics: XP X/h" row below "Expenses"

### 8. Check Metrics Computation
```lua
/script local s = GoldPH_SessionManager:GetActiveSession(); local m = GoldPH_SessionManager:GetMetrics(s); if m then print("xpGained: " .. m.xpGained); print("xpPerHour: " .. m.xpPerHour); print("xpEnabled: " .. tostring(m.xpEnabled)); else print("No metrics"); end
```

## Troubleshooting

### Issue: No "[GoldPH] XP gained" messages
**Possible causes:**
1. At max level (check with step 5)
2. PLAYER_XP_UPDATE event not firing
3. XP state not initialized

**Fix:** Try manually initializing:
```lua
/script local s = GoldPH_SessionManager:GetActiveSession(); if s then s.metrics.xp.enabled = true; print("Enabled XP tracking"); end
```

### Issue: HUD doesn't show metrics row
**Possible causes:**
1. HUD is minimized (expand it)
2. No XP gained yet (xpPerHour = 0)
3. Duration too short

**Fix:** Check if metrics exist:
```lua
/script local s = GoldPH_SessionManager:GetActiveSession(); local m = GoldPH_SessionManager:GetMetrics(s); print("xpEnabled: " .. tostring(m.xpEnabled)); print("xpPerHour: " .. m.xpPerHour); print("anyMetricEnabled: " .. tostring(m.xpEnabled or m.repEnabled or m.honorEnabled))
```

### Issue: "end expected" error on reload
This means there's a syntax error. Check the error message for the line number and file.

## Manual XP Test (If automatic doesn't work)

If the automatic XP tracking isn't working, try manually injecting:

```lua
/script local s = GoldPH_SessionManager:GetActiveSession(); if s and s.metrics and s.metrics.xp then s.metrics.xp.gained = 5000; s.metrics.xp.enabled = true; print("Injected 5000 XP"); GoldPH_HUD:Update(); else print("Cannot inject - check session structure"); end
```

Then check the HUD - you should now see "Metrics: XP X/h" row.

## Full Debug Report

Run this to get a complete report:
```lua
/script loadstring(io.open("Interface/AddOns/GoldPH/Debug_XP.lua", "r"):read("*a"))()
```

Or manually run the debug code from Debug_XP.lua file.

## What the Metrics Row Should Look Like

In the HUD (expanded state), after the "Expenses" row, you should see:
```
Metrics: XP 1.2k/h | Rep 450/h | Hon 300/h
```

(Only showing the metrics that have data)
