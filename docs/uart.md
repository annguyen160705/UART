# UART RTL Design

This project implements a simple **UART transmitter (TX)**, **UART receiver (RX)**, a shared **UART interface**, and a top-level `uart` module that instantiates both blocks.

The design is parameterized by:

- `DATA_WIDTH` — number of UART data bits
- `BAUD_RATE` — UART communication speed
- `CLK_FREQ` — system clock frequency

Default configuration:

```systemverilog
DATA_WIDTH = 8
BAUD_RATE  = 115200
CLK_FREQ   = 100_000_000
```

---

## 1. What is UART?

UART means **Universal Asynchronous Receiver/Transmitter**.

UART is a serial communication protocol. It does not use a shared clock between the transmitter and receiver. Instead, both sides agree on parameters such as baud rate, data width, parity, and stop bits.

A common UART configuration is:

```text
115200 baud, 8 data bits, no parity, 1 stop bit
```

This is often written as:

```text
115200 8N1
```

A typical UART frame is:

```text
IDLE | START | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | STOP
  1  |   0   |              DATA               |      1
```

The UART line is normally **HIGH (`1`) when idle**.

The **START bit is `0`**.

The **STOP bit is `1`**.

UART normally transmits the data bits **LSB first**.

---

# 2. Project Architecture

The design contains four main pieces:

```text
                    +----------------+
                    |      uart      |
                    |                |
                    |  +----------+  |
TX interface ------>|  | uart_tx  |--+----> serial TX signal
                    |  +----------+  |
                    |                |
serial RX signal -->|  +----------+  |
                    |  | uart_rx  |--+----> RX interface
RX interface <------|  +----------+  |
                    +----------------+
```

The modules are:

```text
uart_if.sv   → shared UART interface and modports
uart_tx.sv   → serial transmitter
uart_rx.sv   → serial receiver
uart.sv      → top-level block containing TX and RX
```

---

# 3. UART Interface

The interface is:

```systemverilog
interface uart_if #(parameter DATA_WIDTH = 8);

    logic sig;
    logic [DATA_WIDTH-1:0] data;
    logic valid;
    logic ready;

    modport tx (
        output sig,
        input  data,
        input  valid,
        output ready
    );

    modport rx (
        input  sig,
        output data,
        output valid,
        input  ready
    );

endinterface
```

## 3.1 `sig`

```systemverilog
logic sig;
```

This is the **1-bit serial UART signal**.

It is not the 8-bit data bus.

For example, if the byte is:

```text
8'hA3 = 1010_0011
```

UART sends the bits one at a time:

```text
D0 → D1 → D2 → D3 → D4 → D5 → D6 → D7
 1    1    0    0    0    1    0    1
```

So `sig` carries only one bit at a time.

---

# 4. TX Modport

```systemverilog
modport tx (
    output sig,
    input  data,
    input  valid,
    output ready
);
```

From the point of view of `uart_tx`:

```text
data  → input
valid → input
ready → output
sig   → output
```

Meaning:

```text
valid = 1 → upstream logic has data available
ready = 1 → uart_tx is ready to accept data
sig         → UART serial output
```

The `valid/ready` signals are an **internal data-transfer handshake**. They are not UART start/stop bits.

---

# 5. RX Modport

```systemverilog
modport rx (
    input  sig,
    output data,
    output valid,
    input  ready
);
```

From the point of view of `uart_rx`:

```text
sig   → input
valid → output
ready → input
data  → output
```

Meaning:

```text
sig   → incoming UART serial signal
valid → uart_rx has a complete received byte
ready → downstream logic can accept that byte
data  → received parallel data
```

So the internal RX handshake is:

```text
uart_rx  -- data/valid --> CPU / FIFO / user logic
uart_rx <-- ready ------- CPU / FIFO / user logic
```

When:

```text
valid = 1
ready = 1
```

the received byte can be accepted by the downstream logic.

---

# 6. UART TX

The transmitter has three states:

```systemverilog
typedef enum logic [1:0] {
    STT_WAIT,
    STT_DATA,
    STT_STOP
} statetype;
```

## 6.1 `STT_WAIT`

The transmitter waits for new parallel data.

Important code:

```systemverilog
else if (txif.valid) begin
    state     <= STT_DATA;
    sig_r     <= 0;
    data_r    <= txif.data;
    ready_r   <= 0;
    data_cnt  <= 0;
    clk_cnt   <= PULSE_WIDTH;
end
```

The sequence is:

```text
valid = 1
   ↓
new data is available
   ↓
data_r = txif.data
   ↓
sig_r = 0
   ↓
START bit begins
   ↓
ready_r = 0
   ↓
TX is busy
```

### Important

```systemverilog
sig_r <= 0;
```

creates the **UART START bit** because UART idle is `1` and START is `0`.

`sig_r` itself is not permanently a start-bit register. It is the serial output line whose meaning depends on the current state.

---

# 7. TX Data Transmission

In `STT_DATA`:

```systemverilog
STT_DATA: begin
    if (0 < clk_cnt) begin
        clk_cnt <= clk_cnt - 1;
    end
    else begin
        sig_r <= data_r[data_cnt];
        clk_cnt <= PULSE_WIDTH;

        if (data_cnt == DATA_WIDTH - 1) begin
            state <= STT_STOP;
        end
        else begin
            data_cnt <= data_cnt + 1;
        end
    end
end
```

The transmitter waits one UART bit period and then outputs one data bit.

Because `data_cnt` starts at `0`, the code sends:

```text
data_r[0]
data_r[1]
data_r[2]
...
data_r[7]
```

This is **LSB-first transmission**.

For example:

```text
8'hA3 = 1010_0011

D7 D6 D5 D4 D3 D2 D1 D0
 1  0  1  0  0  0  1  1

TX order:

D0 D1 D2 D3 D4 D5 D6 D7
 1  1  0  0  0  1  0  1
```

The byte is not permanently reversed. Only the **transmission order** is LSB first.

---

# 8. Why `data_tmp_r <= {sig_r, data_tmp_r[DATA_WIDTH-1:1]}` Works in RX

The RX uses a different mechanism:

```systemverilog
data_tmp_r <= {sig_r, data_tmp_r[DATA_WIDTH-1:1]};
```

This shifts the newly received bit into the MSB side of the register.

For example, if the received bits arrive in this order:

```text
D0 D1 D2 D3 D4 D5 D6 D7
 1  1  0  0  0  1  0  1
```

then repeated shifting reconstructs:

```text
D7 D6 D5 D4 D3 D2 D1 D0
 1  0  1  0  0  0  1  1
```

which is the original byte:

```text
1010_0011 = 8'hA3
```

---

# 9. TX Stop Bit

The TX enters `STT_STOP` after all data bits have been transmitted.

```systemverilog
STT_STOP: begin
    if (0 < clk_cnt) begin
        clk_cnt <= clk_cnt - 1;
    end
    else begin
        state <= STT_WAIT;
        sig_r <= 1;
        clk_cnt <= PULSE_WIDTH + HALF_PULSE_WIDTH;
    end
end
```

The stop bit is:

```systemverilog
sig_r <= 1;
```

because UART uses a HIGH stop bit.

The same `sig_r = 1` can also represent the idle state. The FSM state and timing determine whether the `1` is idle or a stop bit.

---

# 10. UART RX Noise Filter

The RX includes a 5-sample majority filter:

```systemverilog
function majority5(input logic [4:0] val);
    return ($countones(val) >= 3);
endfunction
```

This function:

```text
0, 1, 2 ones → output 0
3, 4, 5 ones → output 1
```

Example:

```text
11101 → 4 ones → 1
11000 → 2 ones → 0
```

The function does not sample the signal itself. It only analyzes five samples that were already stored in `sig_q`.

---

# 11. RX Sampling Logic

The RX uses:

```systemverilog
logic [1:0] sampling_cnt;
logic [4:0] sig_q;
logic sig_r;
```

Their roles are:

```text
sampling_cnt → controls when a new sample is taken
sig_q        → stores the 5 most recent samples
sig_r        → filtered 1-bit UART signal
```

The sampling logic is:

```systemverilog
if (sampling_cnt == 0) begin
    sig_q <= {rxif.sig, sig_q[4:1]};
end

sig_r <= majority5(sig_q);
sampling_cnt <= sampling_cnt + 1;
```

Because `sampling_cnt` is only 2 bits wide:

```text
0 → 1 → 2 → 3 → 0 → 1 → 2 → 3 → ...
```

Therefore a new sample is taken every **4 system-clock cycles**.

For a 100 MHz clock:

```text
1 clock = 10 ns
4 clocks = 40 ns
```

---

# 12. `sig_q` Sliding History

The statement:

```systemverilog
sig_q <= {rxif.sig, sig_q[4:1]};
```

means:

```text
new sample enters bit [4]
old [4] moves to [3]
old [3] moves to [2]
old [2] moves to [1]
old [1] moves to [0]
old [0] is discarded
```

Example:

```text
Initial:
11111

new sample = 0
01111

new sample = 1
10111

new sample = 0
01011

new sample = 1
10101
```

So `sig_q` is a **5-sample sliding window**.

---

# 13. Important Timing Detail

With:

```text
CLK_FREQ  = 100 MHz
BAUD_RATE = 115200
```

one UART bit is approximately:

```text
PULSE_WIDTH = CLK_FREQ / BAUD_RATE
            ≈ 100,000,000 / 115,200
            ≈ 868 clocks
```

Therefore:

```text
1 UART bit ≈ 868 system clocks
```

Your RX input sampler takes a sample every 4 clocks:

```text
868 / 4 ≈ 217 samples per UART bit
```

So the signal is sampled much faster than once per UART bit.

The `majority5` filter only looks at a small moving window of five recent samples.

---

# 14. RX FSM

The RX has three states:

```text
STT_WAIT
    ↓
STT_DATA
    ↓
STT_STOP
    ↓
STT_WAIT
```

## 14.1 `STT_WAIT`

The receiver waits for a START bit.

```systemverilog
if (sig_r == 0) begin
    clk_cnt <= PULSE_WIDTH + HALF_PULSE_WIDTH;
    data_cnt <= 0;
    state <= STT_DATA;
end
```

When `sig_r` becomes `0`:

```text
UART idle = 1
START     = 0
```

The RX assumes a new frame has started.

---

# 15. Why `PULSE_WIDTH + HALF_PULSE_WIDTH`?

The RX waits approximately 1.5 bit periods before taking the first data sample.

For the default settings:

```text
PULSE_WIDTH      ≈ 868
HALF_PULSE_WIDTH ≈ 434

868 + 434 = 1302 clocks
```

The reason is that after detecting the START bit, the receiver wants the first data sample to occur near the **center of D0**.

Conceptually:

```text
START       D0        D1        D2
  |----------|----------|----------|
       ↑
       first data sample
```

Sampling near the center of each bit gives better timing tolerance.

---

# 16. RX Data State

The RX data logic is:

```systemverilog
STT_DATA: begin
    if (clk_cnt == 0) begin
        data_tmp_r <= {sig_r, data_tmp_r[DATA_WIDTH-1:1]};
        clk_cnt <= PULSE_WIDTH;

        if (data_cnt == DATA_WIDTH - 1) begin
            state <= STT_STOP;
        end
        else begin
            data_cnt <= data_cnt + 1;
        end
    end
    else begin
        clk_cnt <= clk_cnt - 1;
    end
end
```

The basic sequence is:

```text
wait until clk_cnt == 0
        ↓
sample sig_r
        ↓
shift sample into data_tmp_r
        ↓
reload clk_cnt
        ↓
move to next data bit
```

For 8-bit data:

```text
D0 → D1 → D2 → D3 → D4 → D5 → D6 → D7
```

---

# 17. Last Data Bit vs Stop Bit

Suppose the last data bit is:

```text
D7 = 1
```

The receiver does not confuse it with the stop bit.

Why?

Because the FSM state and counter determine what the `1` means.

During `STT_DATA`:

```text
sig_r = 1
clk_cnt = 0
```

can mean:

```text
D7 = 1
```

After that sample:

```text
state = STT_STOP
```

and the counter is reloaded for the next bit period.

Only after the appropriate stop-bit timing does the RX check the stop bit.

So:

```text
STT_DATA + sig_r = 1 → data bit is 1
STT_STOP + correct timing + sig_r = 1 → stop bit is 1
```

The value alone is not enough; **state + timing + signal** determine the meaning.

---

# 18. RX Stop State

A safer implementation of the stop state is:

```systemverilog
STT_STOP: begin
    if (clk_cnt > 0) begin
        clk_cnt <= clk_cnt - 1;
    end
    else if (sig_r) begin
        state <= STT_WAIT;
    end
end
```

The logic is:

```text
Is clk_cnt > 0?
    │
    ├── YES → decrement counter
    │
    └── NO
         ↓
     Is sig_r = 1?
         │
         ├── YES → valid stop bit → WAIT
         └── NO  → remain in STOP
```

This is preferable to blindly doing:

```systemverilog
clk_cnt <= clk_cnt - 1;
```

when `clk_cnt` may already be zero.

---

# 19. RX `valid_r`

After the complete UART frame is received:

```systemverilog
assign rx_done = (state == STT_STOP) && (clk_cnt == 0);
```

The output logic then does:

```systemverilog
else if (rx_done && !valid_r) begin
    valid_r <= 1;
    data_r <= data_tmp_r;
end
```

This means:

```text
complete byte received
        ↓
copy data_tmp_r → data_r
        ↓
valid_r = 1
```

`valid_r = 1` tells downstream logic:

> “A complete received byte is available in `data_r`.”

Then:

```systemverilog
else if(valid_r && rxif.ready) begin
    valid_r <= 0;
end
```

means:

```text
valid = 1
ready = 1
    ↓
byte accepted
    ↓
valid = 0
```

---

# 20. Valid/Ready vs UART Start/Stop

It is very important not to mix these concepts.

## UART protocol signals

```text
sig = serial UART line

START = 0
DATA  = data bits
STOP  = 1
IDLE  = 1
```

## Internal RTL handshake

```text
valid = data is available
ready = receiver can accept data
```

They are different layers:

```text
           UART protocol
                │
                ▼
              sig
                │
                ▼
        UART TX / UART RX
                │
                ▼
       valid / ready handshake
                │
                ▼
       CPU / FIFO / user logic
```

---

# 21. Complete TX Example

Suppose:

```text
TX data = 8'hA3
```

Binary:

```text
1010_0011
```

Because UART is LSB first:

```text
D0 D1 D2 D3 D4 D5 D6 D7
 1  1  0  0  0  1  0  1
```

The complete frame is:

```text
START D0 D1 D2 D3 D4 D5 D6 D7 STOP
  0    1  1  0  0  0  1  0  1    1
```

So the serial signal is:

```text
0 1 1 0 0 0 1 0 1 1
```

Each bit lasts approximately 868 system-clock cycles with the default configuration.

---

# 22. Complete RX Example

The RX sees the serial stream:

```text
0 1 1 0 0 0 1 0 1 1
```

The receiver interprets:

```text
0        → START
1        → D0
1        → D1
0        → D2
0        → D3
0        → D4
1        → D5
0        → D6
1        → D7
1        → STOP
```

Then it reconstructs:

```text
D7 D6 D5 D4 D3 D2 D1 D0
 1  0  1  0  0  0  1  1
```

which gives:

```text
1010_0011 = 8'hA3
```

---

# 23. TX and RX Can Work Simultaneously

UART is normally full-duplex when TX and RX are separate signals.

```text
Device A                         Device B

TX ----------------------------> RX
RX <---------------------------- TX
```

Therefore, TX and RX can operate at the same time.

For your RTL top module:

```systemverilog
module uart (...);
```

both are instantiated:

```text
+-------------------------+
|          uart           |
|                         |
|  +--------+             |
|  | uart_tx|             |
|  +--------+             |
|                         |
|  +--------+             |
|  | uart_rx|             |
|  +--------+             |
|                         |
+-------------------------+
```

They are independent state machines, although they can share the same `clk` and `rstn`.

---

# 24. Important RTL Notes

## 24.1 `sampling_cnt` does not slow the system clock

```systemverilog
logic [1:0] sampling_cnt;
```

The system still runs at 100 MHz.

The counter only controls how often `rxif.sig` is sampled.

```text
100 MHz system clock
        ↓
0 → 1 → 2 → 3 → 0 → ...
        ↓
new sample every 4 clocks
```

---

## 24.2 Counter wrap-around is automatic

Because `sampling_cnt` is 2 bits:

```text
2'b00 = 0
2'b01 = 1
2'b10 = 2
2'b11 = 3
```

Then:

```text
3 + 1 = 4 = 3'b100
```

but only 2 bits can be stored:

```text
100 → 00
```

Therefore:

```text
0 → 1 → 2 → 3 → 0 → ...
```

There is no normal `X` value caused by this overflow.

---

## 24.3 `sig_r` is a serial signal, not a data register

In TX:

```systemverilog
sig_r <= 0;
```

can create the START bit.

Later:

```systemverilog
sig_r <= data_r[data_cnt];
```

outputs data bits.

Later:

```systemverilog
sig_r <= 1;
```

outputs the STOP bit and eventually the idle state.

Therefore:

```text
sig_r = current UART serial-line value
```

not:

```text
sig_r = permanently the START/STOP bit
```

---

## 24.4 `majority5` is a filter, not a sampler

This function:

```systemverilog
function majority5(input logic [4:0] val);
    return ($countones(val) >= 3);
endfunction
```

does not control when samples are taken.

Sampling is done by:

```systemverilog
sampling_cnt
```

Storage of recent samples is done by:

```systemverilog
sig_q
```

The filter then processes those samples:

```text
rxif.sig
   ↓
sampling_cnt
   ↓
sig_q (5 recent samples)
   ↓
majority5
   ↓
sig_r
```

---

# 25. Suggested File Structure

A clean project structure could be:

```text
uart_project/
├── rtl/
│   ├── uart_if.sv
│   ├── uart_tx.sv
│   ├── uart_rx.sv
│   └── uart.sv
│
├── tb/
│   └── uart_tb.sv
│
└── README.md
```

---

# 26. Basic Questa Commands

Compile:

```bash
vlog rtl/uart_if.sv rtl/uart_tx.sv rtl/uart_rx.sv rtl/uart.sv tb/uart_tb.sv
```

Start simulation:

```bash
vsim uart_tb
```

Start with easier waveform access:

```bash
vsim -voptargs="+acc" uart_tb
```

Inside the Questa command window:

```tcl
add wave *
run -all
```

Run a fixed amount of time:

```tcl
run 10us
```

Restart:

```tcl
restart -f
```

Quit:

```tcl
quit -f
```

Command-line simulation:

```bash
vsim -c -voptargs="+acc" uart_tb -do "run -all; quit -f"
```

Remember:

```text
vlog → compile source files
vsim → load/run the compiled top-level module
```

Use the testbench module name with `vsim`, not the `.sv` filename.

Example:

```bash
vsim uart_tb
```

not:

```bash
vsim uart_tb.sv
```

---

# 27. Recommended Improvements to the Current Code

The current design is useful for learning, but a few changes would make it cleaner and safer.

### Improvement 1 — Avoid subtraction below zero

Prefer:

```systemverilog
if (clk_cnt > 0)
    clk_cnt <= clk_cnt - 1;
```

instead of subtracting when zero is possible.

### Improvement 2 — Explicitly describe the counter width

For example:

```systemverilog
localparam int PULSE_WIDTH = CLK_FREQ / BAUD_RATE;
localparam int CNT_WIDTH   = $clog2(PULSE_WIDTH + 1);
```

This makes the intended range easier to understand.

### Improvement 3 — Keep localparam dependencies ordered

In the RX module, calculate `PULSE_WIDTH` before using it to calculate `LB_PULSE_WIDTH`, and define `HALF_PULSE_WIDTH` before any expression that references it.

A clearer form is:

```systemverilog
localparam int LB_DATA_WIDTH    = $clog2(DATA_WIDTH);
localparam int PULSE_WIDTH      = CLK_FREQ / BAUD_RATE;
localparam int HALF_PULSE_WIDTH = PULSE_WIDTH / 2;
localparam int LB_PULSE_WIDTH   = $clog2(PULSE_WIDTH + HALF_PULSE_WIDTH + 1);
```

### Improvement 4 — Use clear names

Names such as:

```text
clk_cnt
bit_cnt
rx_data
rx_valid
```

can sometimes be easier to read than generic names such as `data_r` or `sig_r`, especially in larger SoC projects.

---

# 28. Mental Model

The easiest way to remember this design is:

```text
TX SIDE

parallel data
    ↓
valid/ready handshake
    ↓
UART TX FSM
    ↓
START
    ↓
DATA bits (LSB first)
    ↓
STOP
    ↓
serial sig
```

and:

```text
RX SIDE

serial sig
    ↓
sampling
    ↓
5-sample history
    ↓
majority5 filter
    ↓
UART RX FSM
    ↓
DATA bits
    ↓
parallel data
    ↓
valid/ready handshake
```

The most important distinction is:

```text
UART protocol:
    START / DATA / STOP

RTL handshake:
    VALID / READY

They are not the same thing.
```

---

# 29. Final Summary

This UART design uses:

```text
DATA_WIDTH  = 8 bits
BAUD_RATE   = 115200
CLK_FREQ    = 100 MHz
```

which gives approximately:

```text
868 system clocks per UART bit
```

The TX:

```text
accepts parallel data
→ generates START
→ sends 8 data bits LSB first
→ generates STOP
→ returns to idle
```

The RX:

```text
samples serial input
→ keeps five recent samples
→ majority-filters the signal
→ detects START
→ samples eight data bits
→ checks STOP
→ produces parallel data
→ raises valid
```

The top-level `uart` module contains both TX and RX, allowing the two directions to operate independently and simultaneously.
