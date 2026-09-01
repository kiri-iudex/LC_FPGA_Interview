# Light Conversion FPGA Interview Task
## 1. Overview
A two-channel signal generator with independently controllable frequency and duty cycle. Each channel produces a signal with a frequency from 1 Hz to 1 MHz and a duty cycle from 0 % to 100 %, and the two channels are configured independently so that changing one does not disturb the other.

The generator core runs on a 100 MHz clock, while configuration parameters are supplied from a separate, asynchronous 33 MHz clock domain. A clock-domain-crossing (CDC) mechanism transfers the parameters safely between the two domains, handling metastability and guaranteeing that all parameters for a given update are applied as one coherent set.

The design is written in synthesizable VHDL (VHDL-2008) and is organized as a small hierarchy: a top-level module wiring together two signal-generator channels, a CDC arbiter, and per-domain reset synchronizers. Verification is done with self-checking testbenches at both the block level and the top level.
## 2. Quick Start / How to Build and Simulate
## 3. Repository Structure
## 4. Requirements
### 4.1 Technical Requirements
### 4.2 Functional Requirements
## 5. Architecture
### 5.1 Top-Level Block Diagram
### 5.2 Clock Domains
### 5.3 Components
#### 5.3.1 Signal Generator
#### 5.3.2 CDC Arbiter
#### 5.3.3 Reset Synchronizer
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