# UART (SystemVerilog)

A simple, parameterizable UART (Universal Asynchronous Receiver/Transmitter) core written in SystemVerilog, with separate transmit (`uart_tx`) and receive (`uart_rx`) modules connected to the outside world through a shared `uart_if` interface.

## Features

- Configurable data width, baud rate, and system clock frequency
- LSB-first serial transmission (standard UART bit order)
- Simple `valid`/`ready` handshake for both TX and RX data paths
- RX-side noise filtering via 5x oversampling with majority voting
- Mid-bit sampling on receive for improved timing margin
- Clean separation of TX/RX logic behind a single SystemVerilog `interface`

## File Structure

```
.
├── uart.sv       # Top-level module: wires uart_tx + uart_rx together
├── uart_tx.sv    # UART transmitter FSM
├── uart_rx.sv    # UART receiver FSM + noise filter
└── uart_if.sv    # SystemVerilog interface (tx/rx modports)
```

> **Note:** Each module includes the interface via a relative path:
> `` `include "if/uart_if.sv" ``
> Make sure `uart_if.sv` is placed in an `if/` subdirectory relative to your include search path, or update the `` `include `` paths / add the appropriate `+incdir` to your simulator invocation.

## Architecture

```
                ┌─────────────────────────────┐
                │            uart              │
                │                               │
   rxif.rx ───► │  ┌────────────┐               │
                │  │  uart_rx   │               │
                │  └────────────┘               │
                │                               │
   txif.tx ◄─── │  ┌────────────┐               │
                │  │  uart_tx   │               │
                │  └────────────┘               │
                └─────────────────────────────┘
```

The top-level `uart` module simply instantiates `uart_tx` and `uart_rx` and connects each to its own `uart_if` instance (`rxif`, `txif`). TX and RX are otherwise fully independent — there is no internal coupling between them.

## Interface (`uart_if`)

```systemverilog
interface uart_if #(parameter DATA_WIDTH = 8);
   logic                  sig;    // Serial UART line
   logic [DATA_WIDTH-1:0] data;   // Parallel data
   logic                  valid;  // Data valid
   logic                  ready;  // Ready to accept/send data
endinterface
```

| Signal  | `tx` modport | `rx` modport | Description                                  |
|---------|:------------:|:------------:|-----------------------------------------------|
| `sig`   | output       | input        | Physical serial UART line                     |
| `data`  | input        | output       | Parallel data bus                              |
| `valid` | input        | output       | Asserted when `data` is valid                  |
| `ready` | output       | input        | Asserted when the module can accept/send data  |

## Module: `uart_tx`

Transmits parallel data as a serial UART frame (1 start bit, `DATA_WIDTH` data bits, 1 stop bit), sending LSB first.

### Parameters

| Parameter    | Default       | Description                          |
|--------------|---------------|---------------------------------------|
| `DATA_WIDTH` | 8             | Number of data bits per frame         |
| `BAUD_RATE`  | 115200        | Target baud rate                      |
| `CLK_FREQ`   | 100_000_000   | System clock frequency (Hz)           |

### FSM

| State       | Behavior                                              |
|-------------|--------------------------------------------------------|
| `STT_WAIT`  | Idle; waits for `valid`, then latches `data` and drives the start bit |
| `STT_DATA`  | Shifts out each data bit, one per `PULSE_WIDTH` clock cycles |
| `STT_STOP`  | Drives the stop bit (`sig = 1`) for one bit period      |

### Handshake

- `ready` is asserted whenever `uart_tx` can accept new data.
- The external producer asserts `valid` together with `data`; on the next clock, `uart_tx` latches `data`, drives the start bit, and de-asserts `ready` until the frame completes.

## Module: `uart_rx`

Receives a serial UART frame and deserializes it into parallel data, LSB first.

### Parameters

Same as `uart_tx`: `DATA_WIDTH`, `BAUD_RATE`, `CLK_FREQ`.

### Noise Filtering

Incoming `sig` is sampled 5 times per nominal quarter-bit window into a shift register (`sig_q`), and a majority-vote function (`majority5`) filters glitches/noise before the signal is used by the receive FSM. This yields a debounced version of the line (`sig_r`).

### FSM

| State       | Behavior                                                        |
|-------------|--------------------------------------------------------------------|
| `STT_WAIT`  | Watches for a falling edge (start bit) on the filtered signal       |
| `STT_DATA`  | Samples each data bit near the middle of its bit period (mid-bit sampling) and shifts it into `data_tmp_r` |
| `STT_STOP`  | Waits for the stop bit to confirm frame completion (`rx_done`)      |

### Handshake

- Once a full frame is received (`rx_done`), `data_r` is latched and `valid` is asserted.
- `valid` stays asserted until the external consumer asserts `ready`, at which point it is cleared.
- **Caution:** there is no internal buffering/FIFO. If the consumer does not assert `ready` before the next frame finishes arriving, the previously received (but unconsumed) data may be overwritten.

## Timing

For both TX and RX:

```
PULSE_WIDTH      = CLK_FREQ / BAUD_RATE       // clock cycles per UART bit
HALF_PULSE_WIDTH = PULSE_WIDTH / 2            // used to align mid-bit sampling on RX
```

With the defaults (`CLK_FREQ = 100 MHz`, `BAUD_RATE = 115200`), each UART bit lasts `PULSE_WIDTH ≈ 868` clock cycles.

## Example Instantiation

```systemverilog
uart_if #(.DATA_WIDTH(8)) rxif();
uart_if #(.DATA_WIDTH(8)) txif();

uart #(
    .DATA_WIDTH(8),
    .BAUD_RATE (115200),
    .CLK_FREQ  (100_000_000)
) uart_inst (
    .rxif (rxif.rx),
    .txif (txif.tx),
    .clk  (clk),
    .rstn (rstn)
);

// Drive the physical RX line:
assign rxif.sig = uart_rx_pin;

// Drive the physical TX line:
assign uart_tx_pin = txif.sig;

// Send a byte:
// txif.data = 8'hA5; txif.valid = 1; wait for txif.ready to pulse.

// Receive a byte:
// wait for rxif.valid; read rxif.data; assert rxif.ready to acknowledge.
```

## Simulation Notes

- Both `uart_tx` and `uart_rx` reset to `STT_WAIT` on `!rstn` (active-low reset).
- `DATA_WIDTH`, `BAUD_RATE`, and `CLK_FREQ` should be chosen so that `CLK_FREQ / BAUD_RATE` divides cleanly enough to keep timing error low; large mismatches will accumulate bit-timing drift over a frame.
- No testbench is included in this repository. A self-checking loopback testbench (connecting `txif.sig` directly to `rxif.sig`) is a good starting point for verification.

## License

`uart_rx.sv` and `uart.sv` are derived from a design by Yuya Kudo (2019), released under the MIT License. See the license header in those files for full terms.
