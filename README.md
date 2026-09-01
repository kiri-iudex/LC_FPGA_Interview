# Light Conversion FPGA Interview Task
## 1. Overview
A two-channel signal generator with independently controllable frequency and duty cycle. Each channel produces a signal with a frequency from 1 Hz to 1 MHz and a duty cycle from 0 % to 100 %, and the two channels are configured independently so that changing one does not disturb the other.

The generator core runs on a 100 MHz clock, while configuration parameters are supplied from a separate, asynchronous 33 MHz clock domain. A clock-domain-crossing (CDC) mechanism transfers the parameters safely between the two domains, handling metastability and guaranteeing that all parameters for a given update are applied as one coherent set.

The design is written in synthesizable VHDL and is organized as a small hierarchy: a top-level module wiring together two signal-generator channels, a CDC arbiter, and per-domain reset synchronizers. Verification is done with self-checking testbenches at both the block level and the top level.
## 2. Quick Start / How to Build and Simulate
## 3. Repository Structure
```
│   .gitignore
│   Makefile
│   README.md
│
├───build
├───simu
├───src
│       cdc_arbiter.vhd
│       reset_sync.vhd
│       sig_generator.vhd
│       sync_2ff.vhd
│       two_ch_sig_generator.vhd
│
└───tb
        cdc_arbiter_tb.vhd
        reset_sync_tb.vhd
        sig_generator_tb.vhd
        sync_2ff_tb.vhd
        two_ch_sig_generator_tb.vhd
```
Source files (`src/`) and their roles:
-   `two_ch_sig_generator.vhd` - top-level module. Instantiates two signal-generator channels, the CDC arbiter, and two reset synchronizers, and wires them together.
-   `sig_generator.vhd` - a single PWM/frequency channel. Counter-plus-comparator core with pending/active parameter staging and boundary-aligned atomic update. Generic `P_DEFAULT` sets the reset-time period.
-   `cdc_arbiter.vhd` - clock-domain-crossing controller. Slow-domain (33 MHz) request/acknowledge FSM plus fast-domain (100 MHz) capture logic. Carries the two channels parameters across as one coherent set and emits a single `load` pulse.
-   `sync_2ff.vhd` - generic-free 2-flip-flop single-bit synchronizer, used for the `req`/`ack` handshake bits inside the arbiter.
-   `reset_sync.vhd` - reset synchronizer (asynchronous assert, synchronous de-assert). One instance per clock domain.

Testbenches (`tb/`):

-   `two_ch_sig_generator_tb.vhd` - top-level, end-to-end, self-checking testbench (drives the commit interface, checks both channel outputs). Covers the full section-7 scenario list.
-   `sig_generator_tb.vhd` - single-channel self-checking testbench.
-   `cdc_arbiter_tb.vhd` - CDC arbiter self-checking testbench.
-   `reset_sync_tb.vhd` - reset-synchronizer self-checking testbench.
-   `sync_2ff_tb.vhd` - 2-FF synchronizer testbench.
## 4. Requirements
### 4.1 Technical Requirements
-  The solution must be implemented in VHDL.
-   Signal generator core clock runs with a 100 MHz frequency.
-   Control-parameter interface runs from a separate, asynchronous 33 MHz clock.
-   The solution must be synthesizable for FPGA.
### 4.2 Functional Requirements
-   Two independent output channels.
-   Each channel independently configurable for frequency and pulse width (duty cycle / PWM).
-   Channel independence: changing one channel's parameters must not affect the other channel's operation.
-   Frequency range: 1 Hz to 1 MHz.
-   Duty-cycle range: 0 % to 100 %, including the edge values:
    -   0 % - output constantly low.
    -   100 % - output constantly high.
-   Parameter updates must be glitch-free: no unplanned short pulses, no extra edges, no incomplete or wrong-length periods, no transient glitches.
-   A channel's frequency and duty must be applied together as one coherent set, so a new frequency is never briefly combined with an old duty (or vice versa).
-   Reliable CDC of the four parameters (ch0 freq, ch0 duty, ch1 freq, ch1 duty) from the 33 MHz domain to the 100 MHz domain, with metastability management, multi-bit integrity, and no loss or double-application.
-   Deterministic reset state: after reset the outputs are in a known state, no random pulses are produced, and the CDC and parameter logic start from a known state.
## 5. Architecture
### 5.1 Top-Level Block Diagram
![Top level design](/img/top_lvl_design.png)
The data path is:

```
   33 MHz domain            |     100 MHz domain
                            |
  data provider --commit--> | 
   (freq/duty, per channel) |
            |               |
            v               |
      +-------------+       |    +--------------------+
      | CDC arbiter |==load,params==>| sig_generator ch0 |--> Ch0
      | (req/ack +  |       |    +--------------------+
      |  busy FSM)  |==load,params==>| sig_generator ch1 |--> Ch1
      +-------------+       |    +--------------------+
            ^  ^            |          ^
            |  |            |          |
   rst33 ---+  |            |  rst100 -+
      (reset_sync 33)       |     (reset_sync 100)
                            |
        external async reset feeds both reset synchronizers

```

The clock-domain boundary passes through the CDC arbiter: its request FSM lives in the 33 MHz domain and its data-capture logic in the 100 MHz domain. Both signal generators and the fast side of the arbiter are in the 100 MHz domain.
### 5.2 Clock Domains
There are two asynchronous clock domains:
-   33 MHz domain: receives configuration parameters and the `commit` signal, runs the CDC request FSM, and drives the `busy` signal back to the data provider.
-   100 MHz domain: the signal generator cores, the fast side of the CDC arbiter, and the generated outputs.

The only signals that cross between domains are the single-bit CDC handshake lines (`req`, `ack`), each passed through a 2-FF synchronizer, and the parameter data bus, which is held stable and captured under handshake control (never passed bit-by-bit through synchronizers). See 6.4.
### 5.3 Components
#### 5.3.1 Signal Generator
The Signal Generator `sig_generator` produces one output channel. It is a free-running counter compared against two registers: the period `P` (counter wrap point) sets the frequency, and the high-time `H` (compare threshold) sets the duty cycle. The output is high while `count < H` and the counter wraps at `P - 1`, giving frequency `f_clk / P` and duty `H / P`. Parameters are double-buffered (pending vs active) and swapped atomically at a period boundary. A generic `P_DEFAULT` (range 100 to 100_000_000) sets the period held after reset. See 6.1.
#### 5.3.2 CDC Arbiter
Clock Domain Crossing is handled by the CDC Arbiter. `cdc_arbiter` moves the four parameters from the 33 MHz domain to the 100 MHz domain as a single coherent set. A slow-domain FSM (IDLE / WAIT_ACK / WAIT_CLR) latches the parameters on `commit`, raises `req`, and asserts `busy`. The fast domain detects the synchronized `req`, captures the (stable) data in one shot, emits a one-cycle `load` pulse, and sends `ack` back to the slow domain. See 6.4.
#### 5.3.3 Reset Synchronizer
`reset_sync` provides an asynchronous-assert, synchronous-de-assert reset. One instance per clock domain converts the single external asynchronous reset into a clean, domain-local reset that releases synchronously to that domain's clock. See 6.5.
#### 5.3.4 Data Converter (optional / out of scope)
## 6. Design Details
### 6.1 Output Signal Generation
Each channel is a single free-running counter with a comparator:

-   The counter increments every 100 MHz cycle and wraps to 0 when it reaches `P - 1`. The wrap point sets the frequency: `f_out = f_clk / P`.
-   The output is high while `count < H`, low otherwise. This sets the duty cycle: `duty = H / P`. A 50 % duty at a given frequency is simply the special case `H = P / 2` (a square wave).

The two edge cases fall out of the same comparator with no special handling: `H = 0` gives a constantly low output (0 %), and `H = P` gives a constantly high output (100 %) with no one-cycle dip at the wrap, because `count` only ever reaches `P - 1`.

Parameters are double-buffered. Incoming values are staged into pending registers (`P_pending`, `H_pending`) and a `update_ready` flag is set. The pending set is copied into the active registers only at a period boundary (when the counter is about to wrap). This is what makes updates glitch-free and atomic:

-   Applying at the period boundary means the current period always completes fully, so there are no partial or wrong-length periods.
-   Copying `P` and `H` on the same clock edge means a new frequency is never briefly paired with an old duty. The set is applied coherently.

Design decision - when parameters take effect: new parameters are applied at the next period boundary, not immediately. The alternative (restart the counter immediately on update) would truncate the in-progress period, which the specification forbids. The cost of boundary-apply is that a change takes effect after up to one current period (worst case about 1 s at 1 Hz). This is the correct trade-off given the no-partial-period requirement.

The `update_ready` flag is owned by a single process and is a set/consume flag: it is set when a new set is staged and cleared when the set is applied at a boundary. On the rare cycle where a new load and a period boundary coincide, the apply is ordered before the capture so that the newly arrived set is retained and applied at the following boundary rather than being dropped.
### 6.2 Parameter Representation
The generator operates on cycle counts (period `P` and high-time `H`, both in 100 MHz clock cycles) rather than physical units (Hz, %). This keeps the generator a pure counter and comparator and keeps all arithmetic out of the fast clock domain. The conversion from physical units to cycle counts is assumed to occur upstream (in the data provider or in a dedicated 33 MHz conversion stage) before the values enter the CDC.

Definitions (for `f_clk = 100_000_000`):

-   `P = f_clk / f_out` (period in cycles)
-   `H = P * duty_percent / 100` (high-time in cycles)

Why cycle counts and not physical units:

1.  Arithmetic (a divide for `P`, a multiply for `H`) stays off the 100 MHz datapath, where timing slack is smallest.
2.  The generator is unit-agnostic and reusable, independent of how the host expresses frequency and duty.
3.  The required endpoints are exact integers: `P = 100_000_000` for 1 Hz and `P = 100` for 1 MHz. This is why a counter-plus-comparator was chosen over a DDS phase accumulator, which would quantize frequency and could not hit these endpoints exactly, and would complicate duty control.

Bit width: the largest period (1 Hz) needs 27 bits and the design uses 32-bit values for `P`, `H`, and the counter, covering the range with margin and matching the 32-bit words carried across the CDC.

Note on port names: the generator's parameter ports carry `P` and `H` as cycle counts. Where a name suggests a physical unit (for example `islv32_freq`), its content is the period in cycles, and `islv32_duty_cycle` is the high-time in cycles.
### 6.3 Input Validation and Clamping
Implementation status: validation is documented here as part of the extended architecture and is out of scope for this submission. The generator assumes pre-validated cycle counts.

If included, validation belongs in the 33 MHz conditioning stage, before the CDC, so only known-good values ever cross. Two classes of illegal input are handled:

-   Period `P` outside `[P_MIN, P_MAX] = [100, 100_000_000]` is clamped to the nearest bound (`P > P_MAX` clamps to 1 Hz, `P < P_MIN` clamps to 1 MHz).
-   High-time `H` greater than the period is clamped to `P` (100 % duty). Because `H` is unsigned, the lower bound of 0 is automatic.

Ordering matters: `H` is clamped against the already-clamped `P`, not the raw `P`. Example: a request for 1 MHz (`P = 100`) with `H = 150` is illegal, clamping `H` to the clamped `P` of 100 yields a sane 100 % instead of a nonsensical value.

Design decision - clamp rather than reject: illegal inputs are clamped to the nearest legal value so the generator always has a defined, safe configuration, rather than rejecting or ignoring the update. `H` is clamped to `P` on the assumption that the provider sends coherent `(P, H)` pairs.

Note: the `P_DEFAULT` generic is range-constrained (`natural range 100 to 100_000_000`), so an out-of-range default is caught at elaboration. This guards the compile-time default only. Runtime parameter values arriving over the CDC are the responsibility of the (out-of-scope) validation stage.
### 6.4 CDC Strategy
#### 6.4.1 Chosen strategy
The four parameters cross from 33 MHz to 100 MHz using a four-phase request/acknowledge handshake, with the data bus held stable during the crossing:

-   On `commit`, the slow-domain FSM latches all four parameters into internal registers (freezing them), asserts `req` and `busy` signals.
-   Only the single-bit `req` is synchronized into the 100 MHz domain (via `sync_2ff`). The wide data bus is never passed bit-by-bit through synchronizers.
-   The fast domain detects the rising edge of the synchronized `req`, captures the (now stable) data bus in a single clock, and emits a one-cycle `load` pulse to both generators.
-   The fast domain asserts `ack`. The slow domain synchronizes `ack` back, drops `req`, then de-asserts `busy` and returns to IDLE.

Why this satisfies the requirements:

-   Metastability: only single-bit `req`/`ack` cross asynchronously, each through a 2-FF synchronizer. The wide bus is sampled only when known-stable, so there is no multi-bit metastability.
-   Coherent multi-bit set: the data is latched once and frozen for the whole handshake, then captured on a single fast-domain edge, so all four values (both channels) are applied together.
-   No loss / no double-apply: `busy` backpressure prevents a new commit while a transfer is in flight, and the fast side captures once on the edge of synchronized `req`.

Data-before-req detail: data and `req` are launched on the same slow-clock edge, but the fast domain never samples the data on that edge - the synchronizer delays `req` by at least two fast cycles, by which time the (frozen) bus has long settled. The synchronizer latency provides the required setup margin.

Internal-freeze detail: because the crossed data is an internal latched copy, the input ports may change freely during the handshake, the provider only needs the inputs stable at the `commit` edge. The `busy`/FSM-state lock is what keeps the internal copy frozen.
#### 6.4.2 Alternatives
-   Asynchronous FIFO: built for streaming throughput. Here updates are rare and only the latest coherent set matters, so a FIFO is unnecessary logic and verification overhead.
-   Gray code: valid only when a single bit changes per step (FIFO pointers, counters). Arbitrary parameter values change many bits at once, so gray coding does not apply. The data is held stable instead.
-   Double-flopping each data bit independently: the classic bug - bits can arrive skewed by a cycle, momentarily presenting a corrupted value. Avoided by crossing only `req`/`ack` and holding the bus stable.
#### 6.4.3 Channel coupling note
Both channels' parameters are carried in one payload behind one handshake, and one shared `load` pulse stages both. Channel independence is preserved at the output: each channel latches its own pending set at its own period boundary, so a change to one never disturbs the other's live output. A per-channel CDC (or a channel-select payload) is a possible alternative that would decouple the transfers as well. The shared payload was chosen for simplicity and guaranteed coherency.
### 6.5 Reset Strategy 
Reset uses asynchronous assertion and synchronous de-assertion, implemented with one `reset_sync` per clock domain:

-   Assert is asynchronous: when the external reset drops, the outputs reset immediately without waiting for a clock, so logic never runs briefly before reset takes effect.
-   De-assert is synchronous: on release, a constant `1` is shifted through a 2-FF chain, so the reset output rises only after two clock edges and aligned to the clock. This avoids recovery/removal timing problems on release and ensures the whole domain leaves reset on the same edge.

A single external asynchronous reset feeds both synchronizers. The source domain of that reset is irrelevant, because each synchronizer treats its input as asynchronous and re-times the release to its own clock. Assertion is effectively simultaneous across domains, de-assertion is staggered (each domain releases two of its own clock cycles after the external reset rises), which is correct for independent domains bridged by a CDC.

Reset is active-low throughout (`isl_rst = '0'` asserts). After reset the counters are 0, `H_active = 0` (outputs low), the handshake FSM is in IDLE, and the parameter logic is in a known state.
## 7. Testing and Verification
All testbenches are self-checking (they assert expected behavior and print a single PASSED/FAILED result) and were run under GHDL. Each can also be run under ModelSim or Vivado xsim.
Testbenches:

-   `two_ch_sig_generator_tb.vhd` - top-level, end-to-end. Drives the 33 MHz commit interface, lets the CDC cross the parameters, and checks both channel outputs.
-   `sig_generator.vhd_tb` - single channel.
-   `cdc_arbiter.vhd_tb` - CDC handshake and coherency.
-   `reset_sync.vhd_tb` - async-assert / sync-de-assert behavior.
-   `sync_2ff.vhd_tb` - 2-FF synchronizer.
### 7.1 Test Breakdown
#### 7.1.1 Test 1: Correct Reset Behaviour
![Top level design](/img/test1_sync_resest_deassert.png)

The first test verifies that the reset is functioning correctly: the signals and ports of the signal generator are held in a defined state. The main reset signal `isl_arst_n` de-asserts asynchronously at timestamp `A`, but the actual reset of the signal generator is synchronized to the 100Mhz clock, and de-asserts at timestamp `B`.

![Top level design](/img/test1_correct_reset_behaviour.png)

The second picture shows the after-reset behaviour of the signal generator. Although a new configuration is already provided  to signal generator, it will not be latched, until the initial period is done, which is equal to `P_DEFAULT` and lasts exactly `1us`. After the period is done, new configuration data is loaded into the active comparison registers.
#### 7.1.2 Test 2: Minimal Frequency Test

![Top level design](/img/test2_new_config data_loaded.png)

![Top level design](/img/test2_high_check.png)
This test verifies if the edge case of the slowest frequency, 1 Hz. A full 1 Hz period is 100 million cycles (about 1 s of simulation time), which is impractical to run to completion. The testbench therefore verifies the period logic without completing the period: it loads the 1 Hz configuration as the first configuration after reset (when outputs are low), captures the single high pulse at the start of the period on each channel, and then confirms the outputs remain low for 2000 further cycles - proving the full 32-bit period counter is honoured and nowhere near wrapping.
#### 7.1.3 Test 3: Reset
The third test once again verifies the reset behaviour and is required to clear the 1 Hz and prevents waiting a 1 s until the counting is finished.
#### 7.1.4 Test 4: Two Channel Configuration
![Top level design](/img/test_4.png)

In this test, both output channels are configured with different frequencies and duty cycles. Channel 0 is configured with `50 % at P=20`, channel 1 with `75 % at P=40`. It is important to note, that the P values in this test is outside of the allowed range [1Hz to 1MHz]. This is done to decrease the simulation time.
#### 7.1.5 Test 5: Maximum Frequency Two Channel Configuration
![Top level design](/img/test_4_test_5_overview.png)

This test checks if both channels, configured with the same frequency but different duty cycle, are properly outputting the signal. It is worth noting, that when the new testing data is loaded, the output on channel 1 changes slightly later than on channel 0. This is because, the previous test configured channel 1 with `P = 40`, which is slower than channel 0.

## 8. Assumptions and Known Limitations
-   Parameters are pre-validated cycle counts. The generator assumes the provider (or an upstream conversion/validation stage) supplies `P` and `H` as valid cycle counts within range. Runtime range-checking of the crossed values is out of scope (see 6.3).
-   Parameter format is cycle counts, not Hz/% (see 6.2). Physical-unit conversion is assumed upstream.
-   First-configuration latency after reset. After reset the active period is `P_DEFAULT`, so a channel's output stays at its reset state (low) until the first configuration is applied at the first period boundary (within `P_DEFAULT` cycles). A small `P_DEFAULT` keeps this startup latency short.
-   Update latency. A parameter change takes effect at the next period boundary, so it can take up to one current period to appear (worst case about 1 s at 1 Hz). This is the deliberate cost of glitch-free, no-partial-period updates.
-   Shared-payload CDC. Both channels' parameters cross together on one handshake and share one `load`. channel independence is guaranteed at the output (per-channel boundary-aligned apply), not at the transfer level (see 6.4).
-   Behavioral verification only. Timing closure and CDC/metastability are covered by constraints and static analysis, not by the testbenches (see 7).
-   Constraints are required for correct hardware operation. The synchronizer flip-flops need `ASYNC_REG`, and the CDC data bus needs a `set_max_delay -datapath_only` (or false-path) exception (see 9).
## 9. Tools and Environment