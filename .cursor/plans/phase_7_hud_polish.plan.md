---
name: ""
overview: ""
todos: []
isProject: false
---

# Phase 7 Next Step: HUD Polish

## Scope

Implement HUD polish features: position persistence, scaling via command, income/expense color coding, and tooltips explaining each field. No session history UI in this step.

## 1. HUD Position Persistence

### 1.1 SavedVariables

- In [GoldPH/init.lua](GoldPH/init.lua) `InitializeSavedVariables`, extend `GoldPH_DB.settings` with:
  - `hudPoint` (string, e.g., "TOPRIGHT")
  - `hudRelativePoint` (string, e.g., "TOPRIGHT")
  - `hudXOfs` (number, offset in pixels)
  - `hudYOfs` (number, offset in pixels)

### 1.2 Save position on drag stop

- In [GoldPH/UI_HUD.lua](GoldPH/UI_HUD.lua), update `OnDragStop` handler (around line 57-59):
  - After `StopMovingOrSizing()`, call `hudFrame:GetPoint()` to get current position
  - Save `point, relativeTo, relativePoint, xOfs, yOfs` to `GoldPH_DB.settings`
  - Store relativeTo as `"UIParent"` (or handle nil if relativeTo is UIParent)

### 1.3 Restore position on initialize

- In `GoldPH_HUD:Initialize()` (around line 32-36), after creating frame:
  - Check if `GoldPH_DB.settings.hudPoint` exists
  - If yes, call `hudFrame:ClearAllPoints()` and `hudFrame:SetPoint()` with saved values
  - If no, use default: `SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)`

## 2. HUD Scaling

### 2.1 SavedVariables

- In [GoldPH/init.lua](GoldPH/init.lua) `InitializeSavedVariables`, add to `GoldPH_DB.settings`:
  - `hudScale = 1.0` (default scale)

### 2.2 Apply scale on initialize

- In `GoldPH_HUD:Initialize()`, after setting position:
  - Call `hudFrame:SetScale(GoldPH_DB.settings.hudScale or 1.0)`

### 2.3 Add scale command

- In [GoldPH/init.lua](GoldPH/init.lua) `HandleCommand`, add `/goldph hud scale <0.5-2.0>`:
  - Parse scale value from args[3]
  - Validate range (0.5 to 2.0)
  - Set `GoldPH_DB.settings.hudScale = scale`
  - Apply scale: `hudFrame:SetScale(scale)` (if hudFrame exists)
  - Print confirmation message
- Update `ShowHelp()` to include the new command

## 3. Income/Expense Color Coding

### 3.1 Color helper function

- In [GoldPH/UI_HUD.lua](GoldPH/UI_HUD.lua), add local helper function:
  ```lua
  local function SetValueColor(valueFontString, amount, isIncome, isExpense, isNet)
      if isExpense and amount < 0 then
          valueFontString:SetTextColor(1, 0.3, 0.3)  -- Red for expenses
      elseif isIncome and amount > 0 then
          valueFontString:SetTextColor(0.3, 1, 0.3)  -- Green for income
      elseif isNet then
          valueFontString:SetTextColor(1, 0.84, 0)  -- Gold/yellow for net/gold
      else
          valueFontString:SetTextColor(1, 1, 1)  -- White default
      end
  end
  ```

### 3.2 Apply colors in Update()

- In `GoldPH_HUD:Update()` (around line 280-310):
  - **Gold**: `SetValueColor(hudFrame.goldValue, metrics.cash, false, false, true)` - Gold/yellow
  - **Gold/hr**: `SetValueColor(hudFrame.goldHrValue, metrics.cashPerHour, false, false, true)` - Gold/yellow
  - **Inventory**: Keep white (neutral)
  - **Gathering**: Keep white (neutral, or could be green if positive)
  - **Expenses**: Already has red color (line 302), keep existing logic but use helper
  - **Total value**: `SetValueColor(hudFrame.totalValue, metrics.totalValue, false, false, true)` - Gold/yellow
  - **Total/hr**: `SetValueColor(hudFrame.totalHrValue, metrics.totalPerHour, false, false, true)` - Gold/yellow
  - **Header gold**: `SetValueColor(hudFrame.headerGold, metrics.totalValue, false, false, true)` - Gold/yellow

## 4. HUD Tooltips

### 4.1 Tooltip helper function

- In [GoldPH/UI_HUD.lua](GoldPH/UI_HUD.lua), add local helper:
  ```lua
  local function SetupTooltip(frame, tooltipText)
      frame:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
          GameTooltip:Show()
      end)
      frame:SetScript("OnLeave", function(self)
          GameTooltip:Hide()
      end)
  end
  ```

### 4.2 Add tooltips to all fields

- In `GoldPH_HUD:Initialize()`, after creating each label/value pair:
  - **Gold label/value**: "Current gold balance (gold/silver/copper) in your bags"
  - **Gold/hr label/value**: "Gold earned per hour based on session duration"
  - **Inventory label/value**: "Expected vendor/AH value of vendor trash and rare items (excluding gathering materials)"
  - **Gathering label/value**: "Expected value of gathering materials (ore, herbs, leather, cloth)"
  - **Expenses label/value**: "Total expenses: repairs, vendor purchases, and travel costs"
  - **Total label/value**: "Total economic value: cash + all inventory (expected liquidation value)"
  - **Total/hr label/value**: "Total economic value per hour"
  - **Header gold**: "Total economic value (gold + inventory)"
  - **Header timer**: "Session duration (accumulated in-game time)"

### 4.3 Enhanced gathering tooltip (optional)

- For gathering value tooltip, in `Update()` when setting tooltip dynamically:
  - If `metrics.gatheringTotalNodes` exists and > 0:
    - Show: "Expected value of gathering materials\nTotal nodes: X\nNodes/hour: Y"
    - Optionally list top 3 node types if `metrics.gatheringNodesByType` has entries

## 5. Files to Modify


| File                                   | Changes                                                                                                                        |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [GoldPH/init.lua](GoldPH/init.lua)     | Add `hudPoint`, `hudRelativePoint`, `hudXOfs`, `hudYOfs`, `hudScale` to settings; add `/goldph hud scale` command; update help |
| [GoldPH/UI_HUD.lua](GoldPH/UI_HUD.lua) | Save position on drag stop; restore position on init; apply scale; add color coding; add tooltips to all fields                |


## 6. Testing

- Manual: Drag HUD, reload, verify position persists
- Manual: Use `/goldph hud scale 1.5`, verify HUD scales
- Manual: Hover over each HUD field, verify tooltip appears with correct text
- Manual: Verify color coding (green for income, red for expenses, gold/yellow for net/gold)

