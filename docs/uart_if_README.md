# uart_if — UART Handshake Interface

A parameterized SystemVerilog `interface` that bundles the four signals shared between a UART transmitter and receiver, with two `modport`s (`tx` and `rx`) that give each side a mirrored view of the same wires.

## Definition

```systemverilog
interface uart_if
    #(parameter DATA_WIDTH = 8);

    logic                  sig;
    logic [DATA_WIDTH-1:0] data;
    logic                  valid;
    logic                  ready;

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

## Why It Exists

Instead of declaring 4 (or more, since `data` is `DATA_WIDTH` bits wide) separate ports on every module that needs to talk UART, both `uart_tx` and `uart_rx` connect to a single `uart_if` instance. This:

- Cuts down on port-list clutter and copy-paste errors
- Keeps `DATA_WIDTH` consistent everywhere the interface is used (set once, via the parameter)
- Encodes signal direction *per role* (`tx` vs `rx`) rather than per physical wire, so the same interface can't accidentally be wired backwards between modules

## Parameter

| Parameter    | Default | Description                          |
|--------------|---------|---------------------------------------|
| `DATA_WIDTH` | 8       | Width of the `data` bus, in bits      |

## Signals

| Signal  | Type                    | Description                                     |
|---------|-------------------------|--------------------------------------------------|
| `sig`   | `logic`                 | The physical serial UART line                    |
| `data`  | `logic [DATA_WIDTH-1:0]`| Parallel data bus                                 |
| `valid` | `logic`                 | Asserted when `data` (or `sig`) is meaningful     |
| `ready` | `logic`                 | Asserted when the other side can accept/send data |

## Modport Directions

The same four signals point in **opposite directions** depending on which modport is used — that's the entire purpose of having two modports instead of one:

| Signal  | `tx` modport | `rx` modport |
|---------|:------------:|:------------:|
| `sig`   | `output`     | `input`      |
| `data`  | `input`      | `output`     |
| `valid` | `input`      | `output`     |
| `ready` | `output`     | `input`      |

Intuition for each signal:
- **`sig`** — `tx` drives the serial line out; `rx` reads the serial line in.
- **`data`** — `tx` reads data it needs to send; `rx` writes data it has decoded.
- **`valid`** — `tx` reads "is my input data good to send?"; `rx` writes "is my decoded output good to read?"
- **`ready`** — `tx` writes "I can accept new data now"; `rx` reads "can the outside world accept my decoded data now?"

## Usage Example

```systemverilog
uart_if #(.DATA_WIDTH(8)) txif();
uart_if #(.DATA_WIDTH(8)) rxif();

uart_tx u_tx (
    .txif (txif.tx),   // uart_tx only sees the tx-modport view
    .clk  (clk),
    .rstn (rstn)
);

uart_rx u_rx (
    .rxif (rxif.rx),   // uart_rx only sees the rx-modport view
    .clk  (clk),
    .rstn (rstn)
);
```

Each module only ever sees its own modport — `uart_tx` can't accidentally read `sig` as an input, and `uart_rx` can't accidentally drive `data` as an input, because the modport declaration enforces the correct direction at compile time.

## Notes

- This interface carries **no clock or reset** — those are passed separately to each module.
- It's purely a passive signal bundle; there's no internal logic, storage, or behavior inside it. All the actual protocol logic (framing, timing, noise filtering) lives in `uart_tx` and `uart_rx`.
- Because `sig`, `valid`, and `ready` are single bits regardless of `DATA_WIDTH`, only `data`'s width scales with the parameter.
