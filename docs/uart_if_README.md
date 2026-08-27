# UART Interface (`uart_if`)

## Overview

`uart_if` is a parameterized SystemVerilog interface used by the UART transmitter and receiver.

It groups the following signals:

* `sig` — serial UART signal
* `data` — parallel UART data
* `valid` — data valid
* `ready` — data ready

---

## Parameter

| Parameter    | Default | Description            |
| ------------ | ------: | ---------------------- |
| `DATA_WIDTH` |       8 | Width of parallel data |

---

## Modports

### TX

```systemverilog
modport tx(
    output sig,
    input  data,
    input  valid,
    output ready
);
```

```text
data + valid
     ↓
  UART TX
     ↓
    sig

ready ← UART TX
```

TX receives parallel data and sends it serially through `sig`.

### RX

```systemverilog
modport rx(
    input  sig,
    output data,
    output valid,
    input  ready
);
```

```text
    sig
     ↓
  UART RX
     ↓
data + valid

ready → UART RX
```

RX receives serial data and converts it back to parallel data.

---

## Data Flow

```text
Parallel Data → UART TX → Serial UART

Serial UART → UART RX → Parallel Data
```

`valid` and `ready` are used for handshake on the parallel-data side.

---

## File Structure

```text
uart/
├── if/
│   └── uart_if.sv
├── rtl/
│   ├── uart_tx.sv
│   └── uart_rx.sv
└── README.md
```

---

## License

MIT License.

Original copyright:

```text
Copyright (c) 2019 Yuya Kudo
```
