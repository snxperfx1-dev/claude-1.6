# RE-AUDIT: Verification of Previously Described Fixes Against Spec

## VERDICT: FIX 1+2 HAS A CATASTROPHIC INVERSION — MAKES THE BUG WORSE

The previously described fix to the compression→recursion mapping is **exactly backwards** from what the spec requires. This single error means the "fixed" algo would perform WORSE than the original in high-compression environments.

---

## CRITICAL FINDING: Compression→Recursion Mapping Is Inverted

### What The Fix Implemented

The described fix computes `recRequired` as:
```
Extreme compression (compIdx >= 80) → recRequired = 1
High compression    (compIdx >= 55) → recRequired = 2
Medium compression  (compIdx >= 30) → recRequired = 3
Low compression     (compIdx < 30)  → recRequired = 4
```

The fix's stated reasoning: "high compression = fewer required (tighter loops), low compression = more required (wider loops)."

### What The Spec ACTUALLY Says

The spec is explicit and unambiguous on this point:

> **"High compression: New High → small failures → many recursive cycles → transition"**
> **"Low compression: New High → one curve → transition"**

And in the entry zone context:

> **"High compression: Strike → Failure swing → 3 tiny recursive cycles → Entry"**
> **"Low compression: Strike → Large recursive cycle → Entry"**

The words "many" vs "one" are unambiguous. High compression = MORE recursions required. Low compression = FEWER.

### The F72 Engine Already Models This Correctly

The EXISTING code at line 2208 already has the correct model:

```cpp
// F72 Curve Capacity Engine (DISPLAY ONLY):
double _wavelen = fmax2(0.4, 2.0*(1.0-_oc/100.0));
// Comment: "natural recursion wavelength SHRINKS with compression 
//           (tight zone -> tiny fast loops), so the SAME remaining 
//           distance fits more (smaller) cycles when compressed"
```

- Low compression (_oc=0): wavelength = 2.0 ATR → FEW cycles fit
- High compression (_oc=80): wavelength = 0.4 ATR → MANY cycles fit
- `_depthCap = (_oc>=80.0) ? 5.0 : 4.0` — Extreme compression can fit 5 micro-recursions

**The F72 display engine says "high compression = more cycles" while the fix makes the state machine say "high compression = fewer cycles needed." They CONTRADICT each other.**

### Correct Mapping (Per Spec)

```
Low compression     (compIdx < 30)  → recRequired = 1  (one large curve suffices)
Medium compression  (compIdx >= 30) → recRequired = 2-3
High compression    (compIdx >= 55) → recRequired = 3-4
Extreme compression (compIdx >= 80) → recRequired = 4-5 (many tiny cycles)
```

### Why This Matters

With the inverted mapping:
- In a **high-compression** environment (where the spec says to expect 3-5 tiny recursive cycles), the fix requires only 1 CHoCH. This means the transition completes EVEN FASTER than the original bug — the original at least needed `transferDone` (recDom>=50) which might take 2 breaks.
- In a **low-compression** environment (where the spec says one large curve suffices), the fix requires 4 CHoCHs. This means the algo gets STUCK in transition when it should have already moved to retracement.

**The fix makes high-compression setups worse (premature exit from transition) and low-compression setups worse (stuck in transition). It's wrong in both directions.**

---

## FIX-BY-FIX VERIFICATION

### Fix 1+2: Transition Recursion — BROKEN (Inverted)

| Aspect | Verdict | Detail |
|--------|---------|--------|
| Concept | Correct | Using compression to modulate recursion count is the right idea |
| Direction | **INVERTED** | High comp should = MORE required, not fewer |
| transferDone threshold | Partially fixed | Scaling with compression is right, but wrong direction |
| Failure swing shortcut | Correct concept | Allowing fast exit on failure swing in tight compression |

**Net effect**: Makes things WORSE in the most common high-compression transition scenarios.

### Fix 3: Entry During Terminal Sequence — PARTIALLY CORRECT

| Aspect | Verdict | Detail |
|--------|---------|--------|
| Concept | Correct | Allowing entry during Induction/Liquidation/Terminal is what spec requires |
| Gate condition | **CIRCULAR** | Requires `cur_entryReady=="Entry Active"` which requires `cur_mtfEntryFresh` which requires a rung to already be in Return phase |
| Phase expansion | Good | Adding Retracement Induction / Retracement Liquidity / Terminal Curve is correct |

**Remaining gap**: The `cur_mtfEntryFresh` dependency means you STILL need a Return phase on some rung (typically M1/M3) before the terminal-phase entry can fire on M5. This works for multi-TF confirmation but fails when:
- All rungs are simultaneously in the terminal sequence (synchronized)
- M1 hasn't resolved to Return yet (just starting the terminal strike)

The spec says: "Once the entry cycle starts, hesitation gets you left behind." The fix still requires a resolved Return somewhere before entry — this may still be too late.

**What's missing**: A pure physics-based entry detection that doesn't require ANY phase label. The spec describes it as detecting:
- Dominance has transferred (recDom >= 50 on the owner curve)
- Compression achieved inside the terminal zone
- Counter-impulse fires from the zone

These three conditions together = entry cycle, regardless of what phase label any rung shows.

### Fix 4: cur_entryReady Gates Signals — PARTIALLY CORRECT

| Aspect | Verdict | Detail |
|--------|---------|--------|
| Concept | Correct | Using entry readiness as a signal gate |
| Implementation | **DISPLAY-ONLY TIMING** | `cur_entryReady` is computed inside `if(isLast)` block |
| Backtesting | **BROKEN** | Historical bars never compute this, can't validate |
| Dependency | Circular | Still depends on phase labels via `cur_mtfEntryFresh` |

**The fundamental problem**: The entire F72 block runs only on the last bar:
```cpp
if(isLast){
    // ... entire curve ownership engine here ...
    // cur_entryReady computed here
}
```

This means:
1. In live trading: works on the CURRENT bar only (acceptable)
2. In backtesting: historical bars don't have F72 context (can't validate the fix)
3. In optimization: can't properly score parameter combinations

For the fix to be properly testable, `cur_entryReady` logic needs to run on EVERY processed bar, not just the last one.

### Fix 5: Compression Modulates Required Recursions — BROKEN (Same Inversion)

| Aspect | Verdict | Detail |
|--------|---------|--------|
| Concept | Correct | Exposing recRequired from ComputeSE to Curve Capacity Engine |
| Value | **WRONG** | The recRequired being exposed is the INVERTED value |
| Consistency | **CONTRADICTORY** | F72 says "high comp = more cycles" but exposed recRequired says "high comp = 1 needed" |

Since Fix 5 exposes the inverted `recRequired` from ComputeSE, the Curve Capacity Engine now receives wrong information. The fix described replacing the wavelength formula with the per-TF `recRequired`, but that value is inverted.

### Fix 6 (Second Pass): liqSweep Direction — CORRECT

The fix correctly identifies that:
- `liqSweepBull` (swept ABOVE flipTop) = supply sweep = bearish signal
- `liqSweepBear` (swept BELOW flipBot) = demand sweep = bullish signal (spring)

Mapping: longs need `liqSweepBear` (demand was swept = spring), shorts need `liqSweepBull` (supply was swept = trapped longs). This is correct per market mechanics.

### Fix 7 (Second Pass): te_rrGate Always True — DANGEROUS

| Aspect | Verdict | Detail |
|--------|---------|--------|
| Problem identified | Correct | te_rrGate was blocking all short signals |
| Fix | **TOO AGGRESSIVE** | Removing ALL risk-reward filtering is dangerous |

The correct fix should compute te_tp2 correctly for shorts (target is BELOW entry, stop is ABOVE), not disable the entire gate. With te_rrGate always true, the algo can enter trades with terrible risk-reward (e.g., stop of 3 ATR with target of 0.5 ATR).

**Better fix**: Fix the directional logic of te_tp2_valid for shorts:
```cpp
// For shorts: target is BELOW price, attractor is the zone price will reach
bool te_tp2_valid = direction==1 ? 
    (!naf(eae_primaryAttractorPrice) && eae_primaryAttractorPrice > cl) :  // long: target above
    (!naf(eae_primaryAttractorPrice) && eae_primaryAttractorPrice < cl);   // short: target below
```

Rather than using the attractor as the target (which points to where the wave CAME FROM), use a directional target (FRZ zone in the trade direction, or the flipBot for shorts).

### Fix 8 (Second Pass): HTF Align Exit Removed — CORRECT WITH CAVEAT

Removing `htfAlign` from exit conditions is correct because HTF alignment SHOULD go against the trade during a Return phase (the trade is a counter-HTF execution). However, the fix assumes "ManagePositions() handles this correctly" — this needs verification that ManagePositions actually has:
- Dominance-loss exit
- Curve-ownership-transfer exit
- Time-based exit if ownership doesn't confirm

### Fix 9 (Second Pass): Induction Evidence Without structBias — CORRECT

Removing the `structBias` requirement from induction detection is correct. At the flip zone, structure is still aligned with the prior expansion. Induction is a countertrend event that happens BEFORE structure flips.

---

## REMAINING GAPS EVEN AFTER ALL FIXES

### Gap 1: No "First Strike vs Entry Cycle" Engine

The spec's most critical distinction:
> "Two identical-looking situations have opposite meanings. One is 20 minutes early. The other is right now."

None of the fixes implement a dedicated mechanism to distinguish first-strike from entry-cycle. The fixes use `cur_mtfEntryDom >= 50.0` as a proxy, but this is a threshold on a dominance score — it doesn't model the actual multi-touch pattern:

First Strike:
```
Price touches zone → compression begins → recursive cycles start → NOT READY
```

Entry Cycle:
```
Recursive cycles completing → dominance transferred → compression achieved → READY
```

**What's needed**: Track the NUMBER of zone contacts. First contact = building. Second contact with higher dominance = pre-entry. Third contact OR dominance > 50% = entry.

### Gap 2: No Entry Recursive Engine (ERE)

The spec explicitly calls for two separate recursive engines:
1. **Transition Recursive Engine (TRE)** — "Has New High converted into Retracement yet?"
2. **Entry Recursive Engine (ERE)** — "Are we still building or inside the execution sequence?"

The fixes only address TRE (via the compression-modulated recursion count in ComputeSE). There is NO ERE. The entry zone has its own recursive behavior:

```
Induction → countertrend recursive cycles → compression → liquidation → terminal → entry
```

The number of countertrend cycles inside the entry zone is ALSO compression-dependent, and ALSO needs tracking. Currently the code just checks phase labels — it doesn't track:
- How many induction cycles have occurred inside the zone
- Whether compression inside the zone is achieving (tightening)
- Whether the liquidation phase has started

### Gap 3: Transition Completion Criteria Too Simple

The spec says transition completes when ALL THREE conditions are met:
1. Internal wave energy exhausted
2. Dominant wave loses control
3. Recursive wave becomes dominant

The fix uses: `recBrk >= recRequired && transferDone`. This checks recursion count + dominance transfer, but does NOT check "internal wave energy exhausted." Energy exhaustion would require checking that the expansion energy has fully dissipated — something like `ede_dissipationProgress >= 75` or `obs_ExpansionScore < 20`.

### Gap 4: Failure Swing Logic Is Incomplete

The spec describes failure swings as a SHORTCUT to transition:
> "sometimes when a high gets created at this transition point, price can create a small failure swing, then a massive recursive cycle"

The fix adds a failure swing exit from transition, but the spec says the failure swing starts a MASSIVE recursive cycle — it doesn't complete the transition. A failure swing + subsequent massive recursive cycle = the transition. The failure swing alone is NOT completion.

**Correct logic**: Failure swing should RESET the recursion counter expectations (expect one more large cycle), not EXIT the transition.

### Gap 5: Short-Side Structural Asymmetry

The spec says the algo should "trade both sides of the market fluently at will." But several asymmetries remain even after the second-pass fixes:

1. **rawDemandReturnBelief** — named for demand/long bias, used for BOTH directions. The belief calculation weights are tuned for the long case.

2. **eae_primaryAttractorPrice** — for bearish campaigns, this points to flipTop (ABOVE price, where price came from). The fix removed te_rrGate, but the attractor logic itself is still long-biased.

3. **Direction-specific naming** throughout the code (`demandReturn`, `flipBot` = long target, `flipTop` = short target). This makes the code confusing to verify for short symmetry.

### Gap 6: The "Curve Ownership" Question Is Still Unanswered

The spec's core philosophical requirement:
> "The phase engine shouldn't ask: 'What phase am I in?' It should ask: 'Which curve currently owns price?'"

The fixes still operate on phase labels. Even with expanded entry phases and entry readiness gates, the fundamental question being asked is still "what phase are we in?" The curve ownership computation exists in F72 but remains display-only even after the fixes.

**What would actually implement the spec**: Replace the phase-label entry gate entirely with:

```cpp
bool entryGate = 
    (cur_curveOwner meets entry criteria) &&
    (cur_domTransfer >= 50.0) &&
    (cur_entryReady == "Entry Active" || cur_entryReady == "Terminal") &&
    (cur_compRegime is appropriate for remaining distance);
```

No phase label required at all.

---

## CORRECTED COMPRESSION→RECURSION MAPPING

For both ComputeSE (TRE) and any future ERE:

```cpp
// CORRECT per spec: High compression = MORE tiny recursions required
// "High compression: New High → small failures → many recursive cycles → transition"
// "Low compression: New High → one curve → transition"

int recRequired;
if(compIdx >= 80)      recRequired = 5;  // Extreme: 4-5 micro-recursions (failure swings + tiny loops)
else if(compIdx >= 55) recRequired = 4;  // High: 3-4 recursive cycles
else if(compIdx >= 30) recRequired = 3;  // Medium: 2-3 cycles
else                   recRequired = 1;  // Low: one large curve suffices

// BUT: each recursion is SMALL and FAST in high compression
// So clock-time to completion can actually be SHORTER despite more recursions
// This is why the spec says "transition speed increases" with compression -
// more cycles but each resolves in seconds instead of minutes

// Failure swing handling: a failure swing that gets reclaimed
// DOES NOT complete transition - it starts a larger recursive cycle
// Only count it toward recBrk if it's followed by a completed mini-cycle
```

### Reconciling with Curve Capacity (F72)

The F72 Curve Capacity Engine's wavelength formula is ALREADY CORRECT:
```cpp
double _wavelen = fmax2(0.4, 2.0*(1.0-_oc/100.0));  // low comp ~2 ATR, high comp ~0.4 ATR
cur_expRecDepth = (int)fmin2(_depthCap, fmax2(0.0, MathRound(cur_distFlipAtr/_wavelen)));
```

This correctly says: "with high compression, more cycles fit in the same distance because each cycle is smaller."

When the state machine's `recRequired` matches F72's `cur_expRecDepth`, the two systems agree. The corrected mapping achieves this:

| compIdx | recRequired (state machine) | _wavelen (F72) | cur_expRecDepth at 4 ATR distance |
|---------|---------------------------|----------------|----------------------------------|
| 80+ | 5 | 0.4 ATR | min(5, 4/0.4) = 5 |
| 55-79 | 4 | 0.9 ATR | min(4, 4/0.9) = 4 |
| 30-54 | 3 | 1.4 ATR | min(4, 4/1.4) = 3 |
| <30 | 1 | 2.0 ATR | min(4, 4/2.0) = 2 |

Now they agree. With the inverted mapping they contradict.

---

## SUMMARY TABLE: All Described Fixes Graded

| Fix | Target Bug | Verdict | Critical Issue |
|-----|-----------|---------|----------------|
| Fix 1+2 | Transition is single latch | **BROKEN** | Compression→recursion mapping INVERTED |
| Fix 3 | Entry only in "Demand Return" | **PARTIAL** | Still needs Return on some rung (circular dependency) |
| Fix 4 | cur_entryReady unused | **PARTIAL** | Display-only timing, can't backtest |
| Fix 5 | Compression doesn't modulate | **BROKEN** | Exposes the inverted value from Fix 1 |
| Fix 6 | liqSweep direction | **CORRECT** | Properly fixes long/short sweep semantics |
| Fix 7 | te_rrGate blocks shorts | **DANGEROUS** | Removes all RR filtering instead of fixing direction |
| Fix 8 | HTF exit kills trades | **CORRECT** | Assumes ManagePositions handles ownership exits |
| Fix 9 | Induction needs structBias | **CORRECT** | Properly removes impossible prerequisite |

### Overall Assessment

**2 of 9 fixes are BROKEN** (make things worse)
**2 of 9 fixes are PARTIAL** (improve but don't fully resolve)  
**2 of 9 fixes are DANGEROUS** (fix one problem but create another)
**3 of 9 fixes are CORRECT** (properly resolve their target bug)

### Priority Fixes Needed

1. **INVERT the compression→recursion mapping** in ComputeSE (both instances) — this is a one-line change that fixes the most critical bug
2. **Build a physics-based entry gate** that doesn't require phase labels — dominance + compression + counter-impulse = entry
3. **Move F72 computation out of isLast block** — at minimum, compute entry readiness on every bar
4. **Fix te_rrGate direction** instead of disabling it — shorts need target BELOW price
5. **Add energy exhaustion** to transition completion criteria — not just recursion count + dominance

---

## THE SINGLE LINE THAT FIXES THE WORST BUG

In both ComputeSE() and ComputeSE_V60(), the recRequired computation should be:

```cpp
// BEFORE (WRONG - inverted):
int recRequired = compIdx >= 80 ? 1 : compIdx >= 55 ? 2 : compIdx >= 30 ? 3 : 4;

// AFTER (CORRECT - per spec):
int recRequired = compIdx >= 80 ? 5 : compIdx >= 55 ? 4 : compIdx >= 30 ? 3 : 1;
```

This single inversion fix:
- Makes the state machine agree with F72's curve capacity computation
- Properly holds high-compression transitions until enough micro-recursions have fired
- Allows low-compression transitions to complete after one large curve
- Matches the spec's explicit statements about compression controlling recursion count
