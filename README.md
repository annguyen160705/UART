# UART RTL — Brief README

## 1. What is UART?
UART (Universal Asynchronous Receiver/Transmitter) is a serial communication protocol. It sends data one bit at a time without a shared clock.

Typical frame:

```text
IDLE | START | D0 D1 D2 D3 D4 D5 D6 D7 | STOP
  1  |   0   |          DATA            |  1
```

UART normally sends the **LSB first**.

## 2. UART Parameters

```systemverilog
DATA_WIDTH = 8
BAUD_RATE  = 115200
CLK_FREQ   = 100_000_000
```

For this design:

```text
PULSE_WIDTH = CLK_FREQ / BAUD_RATE
             ≈ 868 clocks / UART bit
```

## 3. UART TX

```text
data + valid
     ↓
  uart_tx
     ↓
START → D0 → D1 → ... → D7 → STOP
```

- `txif.valid = 1`: upstream logic has data.
- `txif.ready = 1`: TX can accept new data.
- `sig_r = 0`: START bit.
- `sig_r = data_r[data_cnt]`: DATA bits.
- `sig_r = 1`: STOP/IDLE.

## 4. UART RX

```text
rxif.sig
   ↓
sample every 4 clk
   ↓
   sig_q
   ↓
majority5 filter
   ↓
   sig_r
   ↓
WAIT → DATA → STOP
   ↓
data_r + valid
```

The RX reconstructs the 8-bit byte from the serial signal.

## 5. `majority5` Filter

`sig_q` stores 5 recent samples of the **1-bit UART signal**, not 5 data bits.

```text
3, 4, 5 ones → 1
0, 1, 2 ones → 0
```

Example:

```text
11101 → four 1s → output 1
00100 → one 1   → output 0
```

This helps reject short noise glitches.

## 6. Valid / Ready

For TX:

```text
valid = "I have data."
ready = "I can accept data."
```

For RX:

```text
valid = "I have received data."
ready = "I can accept the received data."
```

A transfer occurs when:

```text
valid && ready == 1
```

## 7. FSM

### TX

```text
STT_WAIT → STT_DATA → STT_STOP → STT_WAIT
```

### RX

```text
STT_WAIT → STT_DATA → STT_STOP → STT_WAIT
```

## 8. Questa Basics

```bash
vlog uart_if.sv uart_tx.sv uart_rx.sv uart.sv uart_tb.sv
vsim -voptargs="+acc" uart_tb
```

Inside Questa:

```tcl
add wave *
run -all
```

## 9. Main Idea

```text
TX: Parallel data → Serial UART signal
RX: Serial UART signal → Parallel data

UART data = 8 bits
majority5 = 5 samples of one serial bit
```
