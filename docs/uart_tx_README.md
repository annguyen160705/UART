# UART Transmitter

## Overview

This project implements a parameterized **UART Transmitter (`uart_tx`)** in SystemVerilog.

The transmitter receives parallel data through a `valid/ready` handshake interface and serializes the data into a UART transmission frame containing:

* Start bit
* Configurable number of data bits
* Stop bit

The module uses the SystemVerilog interface defined in:

```text
if/uart_if.sv
```

with the TX modport:

```systemverilog
uart_if.tx txif
```

---

## Features

* Parameterized data width
* Configurable baud rate
* Configurable system clock frequency
* Parallel-to-serial conversion
* UART start-bit generation
* UART stop-bit generation
* `valid/ready` input handshake
* 3-state FSM
* SystemVerilog Interface and Modport

---

## Parameters

| Parameter    | Default | Description                  |
| ------------ | ------: | ---------------------------- |
| `DATA_WIDTH` |       8 | Number of UART data bits     |
| `BAUD_RATE`  |  115200 | UART baud rate               |
| `CLK_FREQ`   | 100 MHz | Input system clock frequency |

The module internally calculates:

```systemverilog
LB_DATA_WIDTH    = $clog2(DATA_WIDTH)
PULSE_WIDTH      = CLK_FREQ / BAUD_RATE
LB_PULSE_WIDTH   = $clog2(PULSE_WIDTH)
HALF_PULSE_WIDTH = PULSE_WIDTH / 2
```

`PULSE_WIDTH` represents the approximate number of system-clock cycles used for one UART bit period.

---

## Module Interface

```systemverilog
module uart_tx #(
    parameter DATA_WIDTH = 8,
    parameter BAUD_RATE  = 115200,
    parameter CLK_FREQ   = 100_000_000
)(
    uart_if.tx txif,
    input logic clk,
    input logic rstn
);
```

### Inputs

| Signal       | Description                        |
| ------------ | ---------------------------------- |
| `clk`        | System clock                       |
| `rstn`       | Active-low reset                   |
| `txif.data`  | Parallel data to transmit          |
| `txif.valid` | Indicates that input data is valid |

### Outputs

| Signal       | Description                                    |
| ------------ | ---------------------------------------------- |
| `txif.sig`   | Serial UART TX signal                          |
| `txif.ready` | Indicates that the transmitter can accept data |

---

# Architecture

The transmitter consists of three main functions:

```text
                 txif.data
                 txif.valid
                     |
                     v
          +---------------------+
          |   Input Handshake   |
          |    valid / ready    |
          +---------------------+
                     |
                   data_r
                     |
                     v
          +---------------------+
          |     UART TX FSM     |
          |                     |
          | WAIT -> DATA -> STOP|
          +---------------------+
                     |
                     v
          +---------------------+
          |     Serializer      |
          +---------------------+
                     |
                     v
                  txif.sig
```

---

# UART Frame

The transmitter generates the following UART frame:

```text
        Start          Data Bits             Stop
          |                |                   |
          v                v                   v

Idle    +---+---+---+---+---+---+---+---+---+---+    Idle
────────+   |D0 |D1 |D2 |D3 |D4 |D5 |D6 |D7 |   +────────
        | 0 |                               | 1 |
        +---+-------------------------------+---+
```

For the default configuration:

```text
DATA_WIDTH = 8
```

the data is transmitted **LSB first**:

```text
D0 -> D1 -> D2 -> ... -> D7
```

The current implementation does not include a parity bit.

---

# UART Transmitter FSM

The transmitter uses three states:

```systemverilog
typedef enum logic [1:0] {
    STT_DATA,
    STT_STOP,
    STT_WAIT
} statetype;
```

State flow:

```text
                 valid data
                     |
                     v
+----------+     +----------+
| STT_WAIT | --> | STT_DATA |
+----------+     +----------+
     ^                 |
     |                 | DATA_WIDTH bits
     |                 | transmitted
     |                 v
     |            +----------+
     +------------| STT_STOP |
                  +----------+
```

---

## STT_WAIT

`STT_WAIT` is the idle state.

During idle operation, the UART serial line is held high:

```text
txif.sig = 1
```

The transmitter waits until:

```text
txif.valid = 1
```

When valid input data is detected, the transmitter:

* Stores `txif.data` into `data_r`
* Drives the UART line low to generate the start bit
* Clears `ready`
* Initializes the data-bit counter
* Initializes the baud-rate counter
* Transitions to `STT_DATA`

Conceptually:

```text
WAIT

txif.valid = 1
      |
      v
Capture Data
      |
      v
Start Bit = 0
      |
      v
STT_DATA
```

---

## STT_DATA

`STT_DATA` serializes the parallel input data.

The transmitted bit is selected using:

```systemverilog
sig_r <= data_r[data_cnt];
```

Therefore, transmission begins with:

```text
data_r[0]
```

and continues until:

```text
data_r[DATA_WIDTH-1]
```

`data_cnt` tracks the current data bit.

`clk_cnt` controls how long each UART bit remains on the serial output.

After all `DATA_WIDTH` bits have been transmitted, the FSM transitions to:

```text
STT_STOP
```

---

## STT_STOP

`STT_STOP` generates the UART stop bit.

After the data-bit timing completes, the serial output is returned high:

```text
sig_r = 1
```

The FSM then returns to:

```text
STT_WAIT
```

and prepares for another transmission.

---

# Valid/Ready Handshake

The input side uses a `valid/ready` handshake.

The producer provides:

```text
txif.data
txif.valid
```

while the UART transmitter provides:

```text
txif.ready
```

A new word can be accepted when the transmitter is ready and valid input data is available.

Conceptually:

```text
Producer                         UART TX

data    ------------------------>

valid   ------------------------>

ready   <------------------------

             Input accepted
```

When transmission begins:

```text
ready = 0
```

indicating that the transmitter is busy.

After the transmission completes and the transmitter returns to the waiting state, `ready` is asserted again.

---

# Baud Rate Generation

UART timing is derived from:

```systemverilog
PULSE_WIDTH = CLK_FREQ / BAUD_RATE;
```

For the default configuration:

```text
CLK_FREQ  = 100,000,000 Hz
BAUD_RATE = 115,200 baud
```

the calculated value is:

```text
PULSE_WIDTH = 100,000,000 / 115,200
            = 868
```

Therefore, the design uses approximately **868 system clock cycles per UART bit period**.

The internal counter:

```systemverilog
clk_cnt
```

controls the duration of the start bit, each data bit, and the stop-bit timing.

---

# Internal Signals

| Signal     | Description                                |
| ---------- | ------------------------------------------ |
| `state`    | Current transmitter FSM state              |
| `data_r`   | Stores the parallel data being transmitted |
| `sig_r`    | Internal UART serial output                |
| `ready_r`  | Internal ready signal                      |
| `data_cnt` | Tracks the current transmitted data bit    |
| `clk_cnt`  | Controls UART bit timing                   |

---

# Default Configuration

```text
DATA_WIDTH = 8 bits
BAUD_RATE  = 115200 baud
CLK_FREQ   = 100 MHz
```

The default frame format is therefore:

```text
1 Start Bit
8 Data Bits
No Parity
1 Stop Bit
```

or:

```text
8-N-1
```

---

# Example Transmission

For:

```text
txif.data = 8'b1010_0101
```

the transmitter sends the data LSB first:

```text
Start   D0 D1 D2 D3 D4 D5 D6 D7   Stop

  0      1  0  1  0  0  1  0  1     1
```

The serial sequence is therefore:

```text
0 -> 1 -> 0 -> 1 -> 0 -> 0 -> 1 -> 0 -> 1 -> 1
```

---

# Interface

The module uses:

```systemverilog
uart_if.tx txif
```

The TX modport provides the following directions:

```text
UART TX point of view

txif.sig      OUTPUT
txif.data     INPUT
txif.valid    INPUT
txif.ready    OUTPUT
```

This allows the UART signals and handshake signals to be grouped into a single reusable SystemVerilog interface.

---

# File Structure

```text
uart/
│
├── if/
│   └── uart_if.sv
│
├── rtl/
│   ├── uart_tx.sv
│   └── uart_rx.sv
│
├── tb/
│   └── uart_tb.sv
│
└── README.md
```

---

# Verification

Important test cases include:

* Reset behavior
* Transmission of `8'h00`
* Transmission of `8'hFF`
* Transmission of alternating patterns
* Transmission of random values
* Correct start-bit generation
* Correct stop-bit generation
* Correct LSB-first transmission
* `valid/ready` handshake behavior
* Consecutive transmissions
* Different baud-rate configurations
* Different `DATA_WIDTH` configurations

A typical design flow is:

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

The original copyright notice and permission notice must be included in all copies or substantial portions of the software.
