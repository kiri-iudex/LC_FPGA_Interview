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
### 6.2 Parameter Representation
### 6.3 Input Validation and Clamping
### 6.4 CDC Strategy
#### 6.4.1 Chosen strategy
#### 6.4.2 Alternatives considered
#### 6.4.3 Channel coupling note
### 6.5 Reset Strategy 
## 7. Testing and Verification
## 8. Assumptions and Known Limitations
## 9. Tools and Environment