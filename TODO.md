# GoldPH - Todo List & Improvements

## Critical Bugs (Fix Before Next Phase)

### 1. HUD Visibility After Relog
**Issue**: HUD has to be manually shown (`/goldph show`) after a `/reload` or logout/login, even when a session is active.

**Current Behavior**:
- Session resumes correctly after relog
- HUD data is there but frame is hidden
- User must type `/goldph show` to see it

**Expected Behavior**:
- If session is active after relog, HUD should auto-show
- Should match the visibility state from before relog

**Solution Approach**:
- Save HUD visibility state to SavedVariables
- Add `GoldPH_DB.settings.hudVisible = true/false`
- On `PLAYER_ENTERING_WORLD`, check if active session + hudVisible flag
- Automatically show HUD if both conditions met

**Files to Modify**:
- `init.lua` - Check visibility on PLAYER_ENTERING_WORLD
- `UI_HUD.lua` - Save visibility state when showing/hiding
- SavedVariables structure

**Priority**: HIGH

---

### 2. Session Time Tracking During Logout
**Issue**: Active sessions continue tracking time when player is logged off. A session started at 3pm, logged out at 3:30pm, and logged back in at 5pm will show 2 hours of duration, but only 30 minutes were actually played.

**Current Behavior**:
- `startedAt` is set when session starts
- Duration is calculated as `time() - startedAt` on every metric update
- This continues counting even when logged out

**Expected Behavior**:
- Only count time actually logged in and playing
- Pause duration when logged out
- Resume duration when logged back in

**Solution Approach**:

**Option A: Pause on Logout (Simpler)**
- On `PLAYER_LOGOUT`, calculate duration so far and store it
- Store `pausedAt` timestamp
- On `PLAYER_ENTERING_WORLD`, calculate pause duration and adjust `startedAt` forward
- This way duration calculation continues to work correctly

**Option B: Accumulator Pattern (More Accurate)**
- Change data model to track `accumulatedDuration` instead of relying on startedAt
- On `PLAYER_ENTERING_WORLD`, store `loginAt` timestamp
- On `PLAYER_LOGOUT`, add `(time() - loginAt)` to `accumulatedDuration`
- Duration = `accumulatedDuration + (time() - loginAt)` if logged in

**Recommended**: Option B (accumulator pattern)

**Files to Modify**:
- `SessionManager.lua` - Add `accumulatedDuration` and `currentLoginAt` to session
- `SessionManager.lua` - Modify `GetMetrics()` to use accumulator
- `init.lua` - Handle PLAYER_LOGOUT event to accumulate time
- `init.lua` - Update PLAYER_ENTERING_WORLD to set loginAt

**SavedVariables Changes**:
```lua
Session = {
  id = 1,
  startedAt = 1234567890,  -- Keep for reference
  endedAt = nil,

  -- New fields:
  accumulatedDuration = 0,  -- Seconds played so far
  currentLoginAt = nil,     -- When current login session started (or nil if logged out)

  -- Rest of session...
}
```

**Priority**: HIGH

---

## UI/UX Improvements

### 3. HUD Position Persistence
**Issue**: HUD position resets to default after `/reload`

**Solution**: Save HUD position to SavedVariables

**Files**: `UI_HUD.lua`, SavedVariables

**Priority**: MEDIUM

---

### 4. HUD Scaling/Font Size Options
**Issue**: HUD might be too small/large for some users

**Solution**: Add `/goldph hud scale <0.5-2.0>` command to adjust HUD size

**Files**: `UI_HUD.lua`, `init.lua`

**Priority**: LOW

---

### 5. Income/Expense Color Coding
**Issue**: HUD text is all white, hard to distinguish income from expenses

**Solution**:
- Green text for income/positive values
- Red text for expenses/negative values
- Yellow/gold text for net/cash

**Files**: `UI_HUD.lua`

**Priority**: LOW

---

### 6. Session History Browser
**Issue**: No way to view past sessions except via debug dump

**Solution**: Add `/goldph sessions` command to list recent sessions with summary

**Files**: New `UI_Sessions.lua` or add to `init.lua`

**Priority**: LOW

---

## Quality of Life

### 7. Auto-Start Session on Login (Optional)
**Issue**: User must remember to `/goldph start` every time

**Solution**:
- Add setting: `GoldPH_DB.settings.autoStart = true/false`
- Add command: `/goldph autostart on|off`
- If enabled, automatically start session on PLAYER_ENTERING_WORLD (only if no active session)

**Files**: `init.lua`, SavedVariables

**Priority**: LOW

---

### 8. Session Pause/Resume
**Issue**: User might want to pause session (AFK, taking a break) without stopping it

**Solution**:
- Add `/goldph pause` and `/goldph resume` commands
- Store `pausedAt` timestamp
- Don't count time while paused
- Show "PAUSED" in HUD

**Files**: `SessionManager.lua`, `UI_HUD.lua`, `init.lua`

**Priority**: LOW

---

### 9. Session Notes/Tags
**Issue**: Hard to remember what each session was for

**Solution**:
- Add `/goldph note <text>` to add note to current session
- Add `/goldph tag <tag>` to tag session (e.g., "farming", "dungeons", "questing")
- Show in session history

**Files**: `SessionManager.lua`, `init.lua`

**Priority**: LOW

---

## Data Validation & Safety

### 10. Negative Cash Detection
**Issue**: If cash goes negative due to bugs, no warning

**Solution**: Add invariant check for negative Assets:Cash, warn user

**Files**: `Debug.lua`

**Priority**: MEDIUM

---

### 11. Session Data Backup
**Issue**: If SavedVariables corrupts, all history is lost

**Solution**:
- On session stop, create backup entry
- Keep last N sessions in backup
- Add `/goldph restore` command

**Files**: `SessionManager.lua`, `init.lua`

**Priority**: LOW

---

### 12. Repair Cost Validation
**Issue**: `GetRepairAllCost()` might return incorrect values in some cases

**Solution**:
- Validate repair cost is reasonable (< player's gold, > 0)
- Add warning if repair cost seems wrong
- Option to manually override via `/goldph repair <cost>`

**Files**: `Events.lua`

**Priority**: LOW

---

## Performance

### 13. HUD Update Throttling
**Issue**: HUD updates every 1 second, might be unnecessary

**Solution**:
- Increase update interval to 2-3 seconds
- Or: Only update on ledger changes + periodic refresh

**Files**: `UI_HUD.lua`

**Priority**: LOW

---

### 14. Ledger Balance Caching
**Issue**: `GetBalance()` iterates through balances table on every call

**Solution**: Cache frequently accessed balances (Assets:Cash, etc.)

**Files**: `Ledger.lua`

**Priority**: LOW

---

## Testing & Debug

### 15. Test Data Cleanup
**Issue**: Test injections pollute active session data

**Solution**:
- Add `/goldph test reset` to reset session to clean state
- Or: Add "test mode" that uses separate session

**Files**: `Debug.lua`, `init.lua`

**Priority**: MEDIUM

---

### 16. Invariant Auto-Check Setting
**Issue**: Debug mode auto-checks are verbose, users might want auto-check without verbose logging

**Solution**:
- Separate `debug.enabled` (invariant checks) from `debug.verbose` (logging)
- Allow silent invariant checking

**Files**: `Debug.lua`

**Priority**: LOW

---

## Future Phase Prep

### 17. Item Cache Retry Logic (Phase 3 Prep)
**Issue**: `GetItemInfo()` returns nil on first call, needs retry

**Solution**:
- Implement item cache with retry queue
- Process pending items on timer
- Add warning if item never resolves

**Files**: New `ItemCache.lua` (Phase 3)

**Priority**: N/A (Phase 3)

---

### 18. FIFO Consumption Validation (Phase 4 Prep)
**Issue**: FIFO consumption is complex and error-prone

**Solution**:
- Add extensive validation in Debug mode
- Check that consumed amounts match holdings
- Warn if holdings go negative

**Files**: `Debug.lua`, `Holdings.lua` (Phase 4)

**Priority**: N/A (Phase 4)

---

## Documentation

### 19. In-Game Help Improvements
**Issue**: `/goldph help` is long, hard to read

**Solution**:
- Add categories: `/goldph help session`, `/goldph help debug`, `/goldph help test`
- Add examples for each command
- Colorize output

**Files**: `init.lua`

**Priority**: LOW

---

### 20. Tooltips for HUD
**Issue**: HUD fields don't explain what they mean

**Solution**: Add tooltips on mouseover (if possible in WoW Classic)

**Files**: `UI_HUD.lua`

**Priority**: LOW

---

## Known Issues (Won't Fix / Out of Scope)

### 21. Mail Items
**Issue**: Mailing items removes them from inventory but doesn't track it

**Status**: Out of scope for now (future phase)

---

### 22. Destroying Items
**Issue**: Destroying items removes expected value but doesn't track it

**Status**: Out of scope for now (future phase)

---

### 23. Trading Items
**Issue**: Trading items to another player doesn't track the value change

**Status**: Out of scope for now (future phase)

---

## Implementation Priority

**Must Fix Before Phase 3**:
1. HUD visibility after relog (HIGH)
2. Session time tracking during logout (HIGH)

**Nice to Have**:
3. HUD position persistence (MEDIUM)
10. Negative cash detection (MEDIUM)
15. Test data cleanup (MEDIUM)

**Future Enhancements**:
- Everything else is LOW priority or nice-to-have
- Can be implemented as time allows or by community

---

## Notes

- **Current Phase**: Phase 2 complete (Vendor Expenses)
- **Next Phase**: Phase 3 (Item Looting & Valuation)
- **Recommended**: Fix bugs #1 and #2 before starting Phase 3
- Many LOW priority items can be community contributions
- Focus on core functionality first, polish later
