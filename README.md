# GoldPH - Gold Per Hour Tracker for WoW Classic Anniversary

A session-based gold tracking addon for World of Warcraft Classic Anniversary using double-ledger accounting to prevent double counting.

**Current Version**: 0.1.0-phase1 (Foundation - Looted Gold Only)

## Features (Phase 1)

- ✅ Session-based tracking (start/stop sessions)
- ✅ Looted gold tracking
- ✅ Real-time cash per hour calculation
- ✅ Persistent sessions (survives `/reload`)
- ✅ Draggable HUD display
- ✅ Comprehensive debug/testing system

## Installation

### macOS (Automated)

```bash
./install.sh
```

The script will:
- Auto-detect your WoW Classic installation
- Backup existing installation if present
- Copy addon files to the correct location

### Manual Installation (macOS & Windows)

1. Copy the `GoldPH/` directory to your WoW AddOns folder:
   - **Windows**: `World of Warcraft/_anniversary_/Interface/AddOns/`
   - **Mac**: `/Applications/World of Warcraft/_anniversary_/Interface/AddOns/`


2. Restart WoW or type `/reload` if already in-game

3. You should see: `[GoldPH] Version 0.1.0-phase1 loaded`

## Quick Start

```
/goldph start          # Start tracking session
                       # Go farm gold!
/goldph stop           # Stop and save session
```

The HUD will display:
- Session number
- Time elapsed
- Total cash earned
- Cash per hour

## Commands

### Session Commands
- `/goldph start` - Start a new session
- `/goldph stop` - Stop the active session
- `/goldph show` - Show/hide the HUD
- `/goldph status` - Show current session status
- `/goldph help` - Show all commands

### Debug Commands
- `/goldph debug on|off` - Enable/disable debug mode (auto-run invariants)
- `/goldph debug verbose on|off` - Enable/disable verbose logging
- `/goldph debug dump` - Dump current session state
- `/goldph debug ledger` - Show ledger balances
- `/goldph debug holdings` - Show holdings (Phase 3+)

### Test Commands
- `/goldph test run` - Run automated test suite
- `/goldph test loot <copper>` - Inject test gold (e.g., `/goldph test loot 500`)

## Architecture

GoldPH uses **double-ledger accounting** to ensure accurate tracking without double counting. When you loot gold:

```
Dr Assets:Cash         +500 copper
Cr Income:LootedCoin   +500 copper
```

This ensures that when items are later sold (Phase 4), we can properly remove their expected value from inventory to avoid counting the same value twice.

See [CLAUDE.md](CLAUDE.md) for architecture details and [GoldPH_TDD.md](GoldPH_TDD.md) for technical specification.

## Development Phases

This addon is being developed in 7 incremental phases:

- **Phase 1** (✅ Complete): Looted gold tracking + debug system
- **Phase 2** (Planned): Vendor expenses (repairs, purchases)
- **Phase 3** (Planned): Item looting & valuation
- **Phase 4** (Planned): Vendor sales with FIFO reversals (prevents double counting)
- **Phase 5** (Planned): Quest rewards & travel expenses
- **Phase 6** (Planned): Rogue pickpocketing & lockboxes
- **Phase 7** (Planned): Gathering nodes & UI polish

Each phase is implemented as a separate PR for review. See the [multi-phase plan](.claude/plans/sprightly-gliding-thunder.md) for details.

## Testing

### Manual Testing
1. Start a session: `/goldph start`
2. Loot gold from mobs
3. Check HUD updates in real-time
4. Reload UI: `/reload`
5. Verify session continues
6. Stop session: `/goldph stop`

### Automated Testing
```
/goldph debug on
/goldph test run
```

All tests should pass (green). The test suite includes:
- Basic loot posting
- Multiple loot events
- Zero amount handling
- Invariant validation

### Test Injection (No In-Game Actions Required)
```
/goldph start
/goldph test loot 1000   # Inject 1000 copper
/goldph test loot 500    # Inject 500 copper
/goldph status           # Should show 1500 copper total
```

## Files Structure

```
GoldPH/
├── GoldPH.toc          - Addon manifest
├── init.lua            - Entry point, slash commands
├── Ledger.lua          - Double-entry bookkeeping
├── SessionManager.lua  - Session lifecycle
├── Events.lua          - Event handling (CHAT_MSG_MONEY)
├── Debug.lua           - Debug/testing infrastructure
└── UI_HUD.lua          - Heads-up display
```

## Technical Details

- **Currency Format**: All values stored in copper (integers)
- **Persistence**: Uses SavedVariables (`GoldPH_DB`)
- **WoW Version**: Classic Anniversary (Interface 11504)
- **Lua Version**: 5.1

## Troubleshooting

**HUD not showing?**
- Ensure session is active: `/goldph start`
- Try: `/goldph show`

**Session not persisting after reload?**
- Check SavedVariables are enabled in WoW settings
- Verify `GoldPH_DB` exists: `/dump GoldPH_DB`

**Want to test without looting?**
- Use test injection: `/goldph test loot 500`

**Debug an issue?**
- Enable verbose mode: `/goldph debug verbose on`
- Check session state: `/goldph debug dump`

## Contributing

This addon is developed incrementally following a multi-phase plan. Each phase builds on the previous:
1. Foundation (Phase 1) ✅
2. Expenses (Phase 2)
3. Item valuation (Phase 3)
4. Vendor sales with FIFO (Phase 4) - **Critical for no double counting**
5. Quest/Travel (Phase 5)
6. Pickpocketing (Phase 6)
7. Gathering & UI polish (Phase 7)

See [PHASE1_SUMMARY.md](PHASE1_SUMMARY.md) for Phase 1 implementation details.

## License

This addon is provided as-is for personal use. See technical documentation for implementation details.

## Credits

- **Architecture**: Double-ledger accounting system
- **Implementation**: Multi-phase incremental approach
- **Testing**: Comprehensive debug/test infrastructure

For full technical specification, see [GoldPH_TDD.md](GoldPH_TDD.md).
