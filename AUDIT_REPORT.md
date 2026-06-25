# DEEP AUDIT: Why The Algo Doesn't Trade Like The Spec

## Executive Summary

The algo has a **fundamental architectural mismatch** with the spec. The spec describes a system where **transitions and entries are recursive environments** (variable-depth processes controlled by compression and dominance transfer). The code implements them as a **linear phase ladder** with single-latch state transitions. This means the algo either:

1. **Never fires entries** (because it waits for "Demand Return" phase which can't arrive through the terminal sequence properly), or
2. **Fires too early** (because one CHoCH immediately graduates the transition, skipping 1-4 required recursive cycles).

---

## CRITICAL BUG #1: Transition Is A Single Latch, Not A Recursive Environment

### What The Spec Says

> "The high itself becomes a curve. The first break of internal structure (Phase 2 CHoCH) starts a recursive wave."
>
> "There may be: 1 recursion, 3 recursions, 5 recursions depending on compression."
>
> "Transition completes only when: internal wave energy exhausted AND dominant wave loses control AND recursive wave becomes dominant."

The spec explicitly states Transition is a **recursive environment** containing:
- Internal CHoCH count
- Compression regime
- Failure swings  
- Dominance transfer %
- Variable recursion depth (0-5)

### What The Code Does (ComputeSE, phase state machine)

```cpp
// v60 single-latch 14-phase state machine
if(phaseState==5 && !atExtreme && (recBrk>=1||momExhaust)) phaseState=7;  // ← ONE CHoCH exits!
if(phaseState==7 && transferDone) phaseState=8;                           // ← single latch
```

**phaseState==7** is labeled "Transition Environment" but it's literally just a waypoint between state 5 (New High) and state 8 (Retracement). It does NOT:
- Track how many recursive cycles have occurred vs. how many are needed
- Hold price in the transition while recursion completes
- Use compression to determine recursion depth
- Model failure swings as part of the transition process
- Gate exit from transition based on dominance transfer completing across multiple cycles

### The Damage

The phase machine immediately graduates from "New High" (pst==5) to "Transition" (pst==7) on **a single CHoCH** (`recBrk>=1`). The spec says 1-5 CHoCHs are required depending on compression. This means:

- In a **low-compression environment** (where the spec expects 1 large recursive wave), the code happens to work accidentally.
- In a **high-compression environment** (where the spec expects 3-5 tiny recursive cycles), the code skips all of them and immediately declares transition complete.

**Result**: The retracement phase starts too early. The algo "sees" the wave further along than it actually is. Downstream, this poisons every belief score, wave progress estimate, and entry qualification.

---

## CRITICAL BUG #2: `recBrk>=1` Immediately Exits to Retracement

### What The Spec Says

> "Number of recursive cycles: 0–5 depending on compression."
> 
> "High compression: failure swing → many recursive cycles → transition"
> "Low compression: one curve → transition"

The spec is explicit: compression determines how many recursions are required before the transition is considered complete.

### What The Code Does

```cpp
// Transition from New High (5) to Transition (7):
if(phaseState==5 && !atExtreme && (recBrk>=1||momExhaust)) phaseState=7;
```

**`recBrk>=1`** — literally ONE break and it moves on. The variable `recBrk` is incremented:

```cpp
if((phase2CH||oppBOS)&&recArm&&!atExtreme){ recBrk++; recArm=false; }
```

But there is **no logic** that says "given current compression, require N breaks before allowing phase advancement." The compression index (`compIdx`) is computed:

```cpp
double compIdx = fmin2(100.0, fmax2(0.0,
    (1.0 - fmin2(disp/fmax2(dispThresh,1e-10), 1.0)) * 60.0 +
    (1.0 - fmin2(eff/fmax2(effThresh,1e-10), 1.0)) * 40.0));
```

But it's **never used to modulate the required recursion count**. It only feeds into `recDom` (dominance score):

```cpp
double recDom = fmin2(100.0, fmax2(recBrk*(30.0 - compIdx*0.15), retrFrac*80.0));
```

### The Fix Required

The transition gate should be:

```
requiredRecursions = f(compIdx)
// e.g.: compIdx < 30 → 1 recursion needed
//       compIdx 30-55 → 2-3 recursions needed  
//       compIdx 55-80 → 3-4 recursions needed
//       compIdx >= 80 → 4-5 recursions needed

if(recBrk >= requiredRecursions && transferDone) → advance to Retracement
```

Instead the code does:
```
if(recBrk >= 1) → advance   // always 1, regardless of compression
```

---

## CRITICAL BUG #3: Entry Signal Requires "Demand Return" Phase — Never Fires During Terminal Sequence

### What The Spec Says

> "The flip zone is where the curve becomes alive because this is where the terminal sequence happens."
> "Inside flip zone: Retracement → Induction → Induction High → Liquidation → Terminal Curve → Supply/Demand strike"
> 
> "Once the entry cycle starts, hesitation gets you left behind."

The spec says entry happens **AT the flip zone's terminal sequence completion** — meaning during/after the Induction→Liquidation→Terminal curve completes within the HTF supply/demand.

### What The Code Does (Section 21)

```cpp
bool beliefEntryLong = direction==1 
    && ie1a_currentPhase=="Demand Return"    // ← HARD GATE: must be in Demand Return
    && g_demandReturnBelief>50
    && g_expansionBelief<60
    && g_absorptionBelief>25;

bool longSignal = showSignals && beliefEntryLong 
    && htfAligned && !signalLocked && !withinLongLock 
    && edgePassesFilter && preConvOK_long && inducOK_long 
    && structLongOK && liqSweepOK && obFresh && htfLongOK 
    && erf_entryGate;
```

The **hard requirement** `ie1a_currentPhase=="Demand Return"` means:
- During Induction phase → NO SIGNAL
- During Liquidation phase → NO SIGNAL  
- During Terminal Curve → NO SIGNAL
- Only after the entire cycle resolves into "Demand Return" → signal fires

But by the time the M5 engine registers "Demand Return" as a resolved phase, **the move has already happened**. The spec says the entry is AT the terminal sequence completion, not after the phase machine has fully resolved the return.

### The Deeper Problem

The F72 Curve Ownership Engine (Section 1A) actually does compute `cur_entryReady` with values like "Entry Active", "Pre-entry", "Terminal" — these are **exactly the states the spec describes** for identifying the execution window. But:

```cpp
// cur_entryReady is computed here...
if(cur_mtfEntryFresh)  
    cur_entryReady = (cur_mtfEntryDom >= 50.0 ? "Entry Active" : "Pre-entry");
else if(cur_transState=="TERMINAL"||cur_transState=="APPROACHING FLIP") 
    cur_entryReady = "Pre-entry";
// ...but it's NEVER used in Section 21's signal generation
```

`cur_entryReady` is a **display-only variable**. It's stored in the dashboard state but is **never referenced** by `longSignal` or `shortSignal`.

---

## CRITICAL BUG #4: `cur_entryReady` Never Gates Actual Entry Signals

### What The Spec Says

> "The indicator's ultimate purpose isn't: 'Tell me the phase.' It's: 'Tell me whether the curve is still building or whether the entry cycle has begun.'"
>
> The spec defines ENTRY READINESS states:
> - Not Ready
> - Early
> - Building
> - Pre-entry
> - Entry Active
> - Terminal

### What The Code Does

The F72 section computes `cur_entryReady` with exactly the right logic:

```cpp
if(cur_mtfEntryFresh)                                  
    cur_entryReady = (cur_mtfEntryDom >= 50.0 ? "Entry Active" : "Pre-entry");
else if(cur_transState=="TERMINAL"||cur_transState=="APPROACHING FLIP") 
    cur_entryReady = "Pre-entry";
else if(cur_transState=="TRANSITION COMPLETE"||cur_transState=="RETRACEMENT") 
    cur_entryReady = "Building";
else if(cur_transState=="TRANSITION")                  
    cur_entryReady = "Early";
else                                                   
    cur_entryReady = "Not Ready";
```

But Section 21 doesn't use it:

```cpp
bool longSignal = showSignals && beliefEntryLong 
    && htfAligned && !signalLocked && !withinLongLock 
    && edgePassesFilter && preConvOK_long && inducOK_long 
    && structLongOK && liqSweepOK && obFresh && htfLongOK 
    && erf_entryGate;
// ^^^^^^^^^^^^^^^^
// NO CHECK for cur_entryReady == "Entry Active" or "Terminal"
```

### The Fix Required

The entry signal should be gated by:
```cpp
bool entryReadyGate = (cur_entryReady == "Entry Active" || cur_entryReady == "Terminal");
bool longSignal = ... && entryReadyGate;
```

AND the phase requirement should be loosened from strictly "Demand Return" to include the terminal sequence phases when `cur_entryReady` qualifies them.

---

## CRITICAL BUG #5: Compression Never Modulates Required Recursion Count

### What The Spec Says

> "Compression controls recursion count."
>
> "High compression: New High → small failures → many recursive cycles → transition"  
> "Low compression: New High → one curve → transition"
>
> "Same inside supply/demand."
>
> "The missing variable is: Remaining Curve Capacity"

The spec's core insight: compression + distance to attractor = how many recursive loops can physically fit. This is the "Curve Capacity Engine" the spec describes.

### What The Code Does

The Curve Capacity Engine IS partially implemented in the F72 block:

```cpp
double _wavelen = fmax2(0.4, 2.0*(1.0 - _oc/100.0));  // loop size: low comp ~2 ATR, high comp ~0.4 ATR
double _depthCap = (_oc >= 80.0) ? 5.0 : 4.0;          // Extreme compression can fit a 5th micro-recursion
cur_expRecDepth = (int)fmin2(_depthCap, fmax2(0.0, MathRound(cur_distFlipAtr/_wavelen)));
cur_curveBudget = fmin2(100.0, cur_distFlipAtr * 12.5);  // 8 ATR of room = "full" budget
```

This correctly computes:
- `cur_expRecDepth` — expected recursive depth (0-5)
- `cur_curveBudget` — remaining curve capacity (0-100%)
- `cur_distFlipAtr` — distance to HTF flip in ATR units

**BUT** none of these feed back into the `ComputeSE()` phase state machine. The state machine still uses `recBrk>=1` regardless of what `cur_expRecDepth` says.

### The Disconnect

The code has two separate systems:
1. **ComputeSE()** — the phase state machine that decides transitions (runs per-TF, feeds `se5_ph` etc.)
2. **F72 block** — the curve capacity engine (runs only on `isLast` bar for display)

System 2 knows the answer. System 1 ignores it. The phase machine advances based on `recBrk>=1` while the F72 engine correctly says "you need 3 more recursions." But F72 is display-only.

---

## CRITICAL BUG #6: The Multi-TF Entry Scan Fires Too Late

### What The Spec Says

> "You're supposed to enter" when it's "the entry cycle" not "the first strike."
> The distinction: dominance has transferred to the recursive wave.

### What The Code Does

The MTF entry scan looks for a **fresh transition into Return phase** on any rung:

```cpp
for(int _r=0; _r<6; _r++){
    int _c = _phc[_r], _pc = _prev[_r];
    bool _isRet = (_c==12 || _c==13);        // phase 12=Demand Return, 13=Supply Return
    bool _wasRet = (_pc==12 || _pc==13);
    if(_isRet && !_wasRet && _wt[_r] > _bestWt){  // fresh transition into Return
        cur_mtfEntryDir = (_c==12 ? 1 : -1);
        cur_mtfEntryFresh = true;
        cur_mtfEntryDom = _dm[_r];
    }
}
```

Problem: This detects when a rung's phase machine ALREADY resolved to "Demand/Supply Return." But because Bug #2 means the per-TF engines graduate too quickly from transition, AND because the main entry still hard-gates on `ie1a_currentPhase=="Demand Return"` (Bug #3), this scan provides useful information that never gets acted upon at the right time.

---

## CRITICAL BUG #7: DOE "Wait" Logic Blocks Valid Entries

### What The Code Does (V72.8 DOE)

```cpp
string doe_action = inv_invalidated ? "No Trade" :
    (g_liqg_active && !(liqg_objArrival && liqg_trueCHoCH)) ? "Wait" :
    !erf_entryGate ? "Wait" :
    !te_rrGate ? "Wait" :
    (ie1a_currentPhase=="Demand Return" && direction==1) ? "Long" :
    (ie1a_currentPhase=="Supply Return" && direction==-1) ? "Short" :
    "Wait";
```

Even the V72 Decision Output Engine (the most advanced layer) still hard-gates on `ie1a_currentPhase=="Demand Return"`. It correctly identifies "Wait" conditions but its "Long"/"Short" conditions are identically broken — they require the resolved Return phase.

---

## CRITICAL BUG #8: Exit Logic Kills Trades Prematurely

### What The Code Does (Section 24)

```cpp
bool exitCondition = ...
    || (g_tradeDir!=0 && (ie1a_currentPhase=="Transition Environment" || ie1a_currentPhase=="Retracement"));
```

If the algo DOES somehow enter a trade, it immediately exits when the phase reads "Transition Environment" or "Retracement." But the spec says the entry happens AT the terminal/return sequence — and on smaller timeframes, the higher-TF phase can legitimately read "Transition" or "Retracement" while the entry-TF is in execution mode.

This creates a paradox:
- You can only enter in "Demand Return"
- You exit if phase reads "Transition" or "Retracement"
- The window between these is microscopically small

---

## STRUCTURAL PROBLEM: Two Architectures Fighting Each Other

The code has evolved two parallel systems that contradict:

| System | What It Does | Where It Lives |
|--------|-------------|----------------|
| **ComputeSE() + Section 21** | Linear 14-phase ladder → entry on "Demand Return" | Per-TF engine + main ProcessBar |
| **F72 Curve Ownership** | Recursive depth, compression, dominance, entry readiness | Display-only block at end of ProcessBar |

The **F72 system** is actually closer to what the spec describes. It computes:
- `cur_curveOwner` — which TF owns price
- `cur_transState` — BUILDING / TRANSITION / COMPLETE / APPROACHING FLIP / TERMINAL / ENTRY
- `cur_compRegime` — Low / Medium / High / Extreme
- `cur_recDepth` — recursion count on owner curve
- `cur_domTransfer` — dominance transfer %
- `cur_entryReady` — Not Ready / Early / Building / Pre-entry / Entry Active / Terminal
- `cur_curveBudget` — remaining curve capacity
- `cur_expRecDepth` — expected recursive depth (0-5)
- `cur_entryProb` — entry probability %

**All of this is exactly what the spec asks for.** But it's all display-only. None of it feeds into the actual `longSignal`/`shortSignal` booleans.

---

## ROOT CAUSE SUMMARY

| # | Bug | Spec Requirement | Code Reality | Impact |
|---|-----|-----------------|--------------|--------|
| 1 | Transition is a latch | Recursive environment (1-5 cycles) | Single state between pst==5→pst==7→pst==8 | Phase advances too fast |
| 2 | recBrk>=1 exits transition | Compression controls recursion count | One CHoCH = done | Skips 1-4 required cycles |
| 3 | Entry requires "Demand Return" | Entry at terminal sequence completion | Can't fire during Induction/Liquidation/Terminal | Misses the execution window |
| 4 | cur_entryReady unused | Entry readiness gates execution | Display-only variable | F72's correct answer ignored |
| 5 | Compression doesn't modulate recursions | Compression → recursion depth | compIdx computed, never used as gate | All transitions treated identically |
| 6 | MTF scan fires too late | Detect entry cycle vs first strike | Waits for resolved phase | Detects after the move |
| 7 | DOE hard-gates on phase | Entry during terminal sequence | Same broken phase gate | V72 layer also broken |
| 8 | Exit kills on Transition/Retracement | Hold through execution | Exits if higher-TF shows these phases | Paradoxical tiny window |

---

## PROPOSED FIX ARCHITECTURE

### Phase 1: Make ComputeSE() Transition Actually Recursive

```cpp
// Replace:
if(phaseState==5 && !atExtreme && (recBrk>=1||momExhaust)) phaseState=7;
if(phaseState==7 && transferDone) phaseState=8;

// With:
int requiredRec = compIdx >= 80 ? 5 : compIdx >= 55 ? 4 : compIdx >= 30 ? 3 : compIdx >= 15 ? 2 : 1;
bool transitionComplete = (recBrk >= requiredRec) && transferDone && (recDom >= 50.0);

if(phaseState==5 && !atExtreme && (recBrk>=1||momExhaust)) phaseState=7;  // ENTER transition
if(phaseState==7 && transitionComplete) phaseState=8;                      // EXIT transition only when done
```

### Phase 2: Wire F72 Entry Readiness Into Section 21

```cpp
// Replace hard phase gate with F72 entry readiness:
bool entryPhaseOK = (ie1a_currentPhase=="Demand Return") 
    || (cur_entryReady=="Entry Active") 
    || (cur_entryReady=="Terminal" && cur_mtfEntryFresh);

bool beliefEntryLong = direction==1 
    && entryPhaseOK                        // ← REPLACED hard gate
    && g_demandReturnBelief>50
    && g_expansionBelief<60
    && g_absorptionBelief>25;
```

### Phase 3: Add Entry Readiness Gate

```cpp
bool entryReadyGate = (cur_entryReady=="Entry Active" || cur_entryReady=="Terminal");
bool longSignal = ... && entryReadyGate;   // ← ADD this gate
```

### Phase 4: Fix Exit Logic

```cpp
// Remove the premature exit on Transition/Retracement when entry was qualified:
bool exitCondition = ...
    // Remove this line:
    // || (g_tradeDir!=0 && (ie1a_currentPhase=="Transition Environment" || ie1a_currentPhase=="Retracement"));
    // Replace with dominance-based exit:
    || (g_tradeDir!=0 && cur_domTransfer < 20.0 && cur_transState=="BUILDING");  // curve ownership lost
```

### Phase 5: Feed Curve Capacity Back Into Phase Machine

The `cur_expRecDepth` and `cur_curveBudget` computed in F72 need to be available inside `ComputeSE()`. This requires either:
- Moving the curve capacity calculation INTO ComputeSE() (preferred), or
- Making ComputeSE() accept the required recursion count as a parameter

---

## WHY THE ALGO DOESN'T TRADE

Putting it all together in a single execution flow:

1. Price makes a new high → phaseState=5 ✓
2. One CHoCH occurs → `recBrk>=1` → phaseState=7 (transition "complete" after 1 cycle)
3. `transferDone` (recDom>=50) fires quickly → phaseState=8 (Retracement)
4. Price retraces toward flip zone → Retracement phases advance
5. Terminal sequence begins (Induction → Liquidation → Terminal)
6. **Entry window opens** — but `ie1a_currentPhase` is NOT "Demand Return" yet
7. The move fires WITHOUT the algo
8. Eventually phase resolves to "Demand Return" — **too late, move is done**
9. If a signal does fire late, the exit logic may kill it immediately if the display phase flickers to "Transition" or "Retracement"

**The algo is always 20 minutes late to the party because it waits for a resolved phase label instead of detecting the recursive environment's completion in real-time.**

---

## ADDITIONAL ISSUES (Non-Critical But Degrading)

### A. `transferDone` threshold is too easy to hit

```cpp
bool transferDone = recDom >= 50.0;
```

With `recDom = fmin2(100.0, fmax2(recBrk*(30.0-compIdx*0.15), retrFrac*80.0))`:
- If `recBrk=2` and `compIdx=0`: recDom = 2*30 = 60 → transferDone immediately
- If `retrFrac>0.625`: retrFrac*80 = 50 → transferDone from price alone

A 62.5% retracement OR 2 breaks with low compression → transfer "done". The spec says dominance transfer is a gradual process tracked from 0% to 100%.

### B. The Recursive Engine tracks `recBrk` but doesn't model cycle completion

The spec describes recursive waves as complete mini-cycles:
> "It's going to do its own curve cycle here. It's going to create a mini low and then retrace back to the high itself."

A CHoCH break (`recBrk++`) is just the START of a recursive cycle. The code never checks if the recursive wave actually completed its own mini-cycle before counting it.

### C. F72 runs only on `isLast` bar

```cpp
if(isLast){
    // ... entire F72 curve ownership engine ...
}
```

This means the curve capacity / entry readiness is only computed for the most recent bar. Historical bars don't benefit from this logic, so backtesting can't properly validate F72's contribution.

### D. No "first strike vs entry cycle" distinction in signal logic

The spec's most critical insight:
> "Two identical-looking situations have opposite meanings. One is 20 minutes early. The other is right now."

The code has no mechanism to distinguish between a first touch of supply/demand (patience required) vs. the entry cycle already being active (execution required). The `cur_mtfEntryDom >= 50.0` check in F72 IS this distinction — but it's display-only.

---

## CONCLUSION

The algo has the **right data** (compression, recursion depth, dominance transfer, curve capacity, entry readiness) but uses **none of it** for actual trade decisions. The trading logic (Section 21) operates on a completely separate, broken assumption: that a simple phase label ("Demand Return") is sufficient to time entries.

The fix is architecturally simple but requires careful integration:
1. Make the phase state machine respect compression-modulated recursion requirements
2. Wire `cur_entryReady` into the signal generation
3. Allow entries during the terminal sequence (not just after resolution)
4. Fix the exit logic to use curve ownership rather than phase labels

The F72 Curve Ownership Engine is 90% of the solution — it just needs to be promoted from "display dashboard" to "decision authority."
