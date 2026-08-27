# UART Receiver

## Overview

This project implements a parameterized **UART Receiver (`uart_rx`)** in SystemVerilog.

The receiver accepts a serial UART signal, applies a **5-sample majority noise filter**, detects the start bit, receives the data bits, checks the stop bit, and provides the received parallel data through a `valid/ready` handshake.

The module uses a SystemVerilog interface:

```text
if/uart_if.sv
```

with the RX modport:

```systemverilog
uart_if.rx rxif
```

---

## Features

* Parameterized data width
* Configurable baud rate
* Configurable input clock frequency
* 5-sample majority noise filter
* Start-bit detection
* Serial-to-parallel conversion
* Stop-bit detection
* 3-state FSM
* `valid/ready` output handshake
* SystemVerilog Interface and Modport

---

## Parameters

| Parameter    | Default | Description                  |
| ------------ | ------: | ---------------------------- |
| `DATA_WIDTH` |       8 | Number of UART data bits     |
| `BAUD_RATE`  |  115200 | UART baud rate               |
| `CLK_FREQ`   | 100 MHz | Input system clock frequency |

The module calculates the following local parameters:

```systemverilog
LB_DATA_WIDTH    = $clog2(DATA_WIDTH)
PULSE_WIDTH      = CLK_FREQ / BAUD_RATE
LB_PULSE_WIDTH   = $clog2(PULSE_WIDTH)
HALF_PULSE_WIDTH = PULSE_WIDTH / 2
```

`PULSE_WIDTH` represents the approximate number of system clock cycles for one UART bit period.

---

## Module Interface

```systemverilog
module uart_rx #(
    parameter DATA_WIDTH = 8,
    parameter BAUD_RATE  = 115200,
    parameter CLK_FREQ   = 100_000_000
)(
    uart_if.rx rxif,
    input logic clk,
    input logic rstn
);
```

### Input Signals

| Signal       | Description                                              |
| ------------ | -------------------------------------------------------- |
| `clk`        | System clock                                             |
| `rstn`       | Active-low reset                                         |
| `rxif.sig`   | Serial UART receive signal                               |
| `rxif.ready` | Indicates that the connected logic accepts received data |

### Output Signals

| Signal       | Description                           |
| ------------ | ------------------------------------- |
| `rxif.data`  | Received parallel data                |
| `rxif.valid` | Indicates that received data is valid |

---

# Architecture

The receiver consists of three main blocks:

```text
                  UART RX
                     |
                     v
          +---------------------+
          |  5-Sample Majority  |
          |    Noise Filter     |
          +---------------------+
                     |
                   sig_r
                     |
                     v
          +---------------------+
          |    UART RX FSM      |
          |                     |
          | WAIT -> DATA -> STOP|
          +---------------------+
                     |
                data_tmp_r
                     |
                     v
          +---------------------+
          |   Output Register   |
          | valid/ready control |
          +---------------------+
                     |
                     v
               rxif.data
               rxif.valid
```

---

# 1. Noise Removing Filter

Before entering the UART receiver FSM, the serial input is filtered to reduce the effect of short noise pulses.

The filter uses five samples:

```systemverilog
logic [4:0] sig_q;
```

The input samples are shifted into `sig_q`:

```systemverilog
sig_q <= {rxif.sig, sig_q[4:1]};
```

The function:

```systemverilog
majority5()
```

determines the filtered signal from these five samples.

If the majority of samples are `0`, the output is `0`.

If the majority of samples are `1`, the output is `1`.

The filtered UART signal is stored in:

```systemverilog
sig_r
```

and is used by the UART receiver FSM instead of using `rxif.sig` directly.

---

# 2. UART Receiver FSM

The receiver uses three states:

```systemverilog
typedef enum logic [1:0] {
    STT_DATA,
    STT_STOP,
    STT_WAIT
} statetype;
```

The state flow is:

```text
                 Start bit
                    detected
                       |
                       v
+----------+       +----------+
| STT_WAIT | ----> | STT_DATA |
+----------+       +----------+
     ^                  |
     |                  | DATA_WIDTH bits
     |                  | received
     |                  v
     |             +----------+
     +-------------| STT_STOP |
      Stop bit     +----------+
```

---

## STT_WAIT

`STT_WAIT` is the idle state.

The UART line normally remains high while no transmission is occurring.

The receiver detects a start bit when:

```text
sig_r = 0
```

After detecting the start bit, the receiver initializes:

```text
clk_cnt
data_cnt
```

and transitions to:

```text
STT_DATA
```

The initial sampling delay is based on:

```text
PULSE_WIDTH + HALF_PULSE_WIDTH
```

before the first data bit is sampled.

---

## STT_DATA

`STT_DATA` receives the UART data bits.

`clk_cnt` controls the interval between samples.

When the counter reaches zero, the current filtered UART value is shifted into:

```systemverilog
data_tmp_r
```

using:

```systemverilog
data_tmp_r <= {sig_r, data_tmp_r[DATA_WIDTH-1:1]};
```

`data_cnt` tracks the number of received bits.

After `DATA_WIDTH` bits have been received, the FSM transitions to:

```text
STT_STOP
```

---

## STT_STOP

`STT_STOP` waits for the stop-bit sampling point.

The stop bit is expected to be:

```text
1
```

When `sig_r` is high at the required point, the receiver returns to:

```text
STT_WAIT
```

and waits for another UART frame.

---

# UART Frame

The implementation receives a UART frame in the following form:

```text
       Start          Data Bits             Stop
         |                |                   |
         v                v                   v

Idle   +---+---+---+---+---+---+---+---+---+---+   Idle
───────+   |D0 |D1 |D2 |D3 |D4 |D5 |D6 |D7 |   +───────
       | 0 |                               | 1 |
       +---+-------------------------------+---+
```

With the default configuration:

```text
DATA_WIDTH = 8
```

the receiver accepts eight data bits per frame.

This implementation does not include a parity bit.

---

# 3. Receive Completion

Reception completion is indicated internally by:

```systemverilog
assign rx_done =
    (state == STT_STOP) &&
    (clk_cnt == 0);
```

Therefore, `rx_done` becomes active when the receiver reaches the stop-bit sampling point.

---

# 4. Output Data

The completed UART word is stored in:

```systemverilog
data_r
```

and exposed through:

```systemverilog
rxif.data
```

The receiver indicates valid output using:

```systemverilog
rxif.valid
```

---

# Valid/Ready Handshake

The output side uses a `valid/ready` handshake.

After a UART word is received:

```text
rxif.valid = 1
```

and:

```text
rxif.data = received data
```

The receiver holds the data until the connected logic asserts:

```text
rxif.ready = 1
```

A transfer therefore occurs when:

```text
rxif.valid = 1
        AND
rxif.ready = 1
```

Conceptually:

```text
UART RX                         Consumer

data_r  -----------------------> data

valid   -----------------------> valid

ready   <----------------------- ready

              valid && ready
                    |
                    v
             Transfer complete
```

After the handshake, `valid_r` is cleared.

---

# Internal Signals

| Signal         | Description                                 |
| -------------- | ------------------------------------------- |
| `sampling_cnt` | Controls sampling of the raw UART input     |
| `sig_q`        | Stores five UART input samples              |
| `sig_r`        | Filtered UART signal                        |
| `state`        | Current FSM state                           |
| `data_tmp_r`   | Temporary serial-to-parallel shift register |
| `data_cnt`     | Counts received data bits                   |
| `clk_cnt`      | Controls UART bit sampling timing           |
| `rx_done`      | Indicates completion of a UART reception    |
| `data_r`       | Stores the completed received word          |
| `valid_r`      | Indicates valid output data                 |

---

# Default Configuration

```text
DATA_WIDTH = 8 bits
BAUD_RATE  = 115200 baud
CLK_FREQ   = 100 MHz
```

For this configuration:

```text
PULSE_WIDTH = 100,000,000 / 115,200
            = 868
```

Therefore, the RTL uses approximately **868 system clock cycles per UART bit**.

---

# File Structure

```text
uart/
│
├── if/
│   └── uart_if.sv
│
├── rtl/
│   └── uart_rx.sv
│
├── tb/
│   └── uart_rx_tb.sv
│
└── README.md
```

---

# Verification

Important cases to verify include:

* Reset behavior
* Start-bit detection
* Reception of `8'h00`
* Reception of `8'hFF`
* Reception of random 8-bit values
* Consecutive UART frames
* Correct stop-bit handling
* `ready = 0` while `valid = 1`
* Input noise rejection
* Different baud-rate configurations

A typical verification flow is:

```text
RTL
 |
 v
Compile
 |
 v
Simulation
 |
 v
Waveform Debug
 |
 v
Lint
 |
 v
Synthesis
 |
 v
STA
```

---

# License

This source code is distributed under the MIT License.

Original copyright:

```text
Copyright (c) 2019 Yuya Kudo.
```

The original copyright notice and permission notice must be included in copies or substantial portions of the software.
