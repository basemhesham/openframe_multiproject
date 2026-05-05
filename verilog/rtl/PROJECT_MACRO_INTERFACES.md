# AUC OpenFrame: participant Project Integration & Block Diagrams

This document summarizes how individual designs are mapped to the `project_macro` GPIO ports and provides the functional block diagram for each.

## **Reset Architecture & Hierarchy**

The design utilizes a multi-stage reset strategy to ensure reliable system startup, stable project isolation, and remote recovery capabilities.

### **1. Signal Provenance & Logic Flow**
The primary reset for the `project_macro` is generated within the **Green Macro**, which acts as a dedicated isolation and clock-gating tile. The local reset signal (`proj_reset_n`) is a logical combination of the global system state and the project’s activation status:

$$ \text{proj\_reset\_n} = \text{sys\_reset\_n} \ \& \ \text{proj\_en} $$

*   **`sys_reset_n`**: The global asynchronous system reset.
*   **`proj_en`**: A control bit stored in the Green Macro’s **Shadow Register**. This bit is automatically cleared to `0` whenever **`por_n`** (Power-On Reset) is asserted, ensuring the project starts in a disabled and reset state.

### **2. Unified Reset Handling**
By utilizing the gated reset from the Green Macro, a single `reset_n` input at the project level effectively handles two critical states:
1.  **Hardware Reset**: When `sys_reset_n` is pulled low.
2.  **Power-On Event**: When `por_n` clears `proj_en`, forcing the project into reset regardless of the system reset state.

---

## [0,0] Q-PULSE (ECG Arrhythmia Classifier)
**participant Design Connection:**
The design uses a UART-based communication bridge to feed a 1D CNN inference engine. It focuses on minimal pin usage to handle complex data (187 samples per window).

*   **Interface:** UART (13-bit CSR Packet Protocol)
*   **GPIO Mapping:** 
    *   `gpio_bot_in[1]`: `rx` (Input)
    *   `gpio_bot_out[0]`: `uart_tx_w` (Output)
*   **Reset Behavior:** The participant handles the reset by logically ANDing the gated `reset_n` and the global `por_n` into the core's `arst_n` signal. Additionally, a "Soft Reset" is implemented via Bit [12] of the UART packet for remote core recovery.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        .arst_n(reset_n & por_n), // Asynchronous reset for the core
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** Correctly handled. `gpio_bot_oeb[0]` is tied to `1'b0` (Output) for UART TX, while `gpio_bot_oeb[1]` remains at the default `1'b1` (Input) for UART RX.
    *   **Drive Mode:** Uses the default `3'b110` (Strong push-pull) for the TX pin and `3'b001` (Input only) for the RX pin to ensure reliable serial communication. The participant also explicitly set the drive mode for all unused GPIOs to `3'b001` (Input only).

### Block Diagram:
*Note: `reset_n` is the gated system reset, `por_n` is the raw power-on reset.*

```text
           PROJECT MACRO [0,0]
        ┌──────────────────────────────────────────────────┐
        │      ┌──────────┐      ┌──────────────┐          │
bot_in[1]─────►│ UART RX  │─────►│ UART-to-AXIS │          │
        │      │ Receiver │      │    Bridge    │          │
        │      └──────────┘      └──────┬───────┘          │
        │                               │ (ECG Samples)    │
        │      ┌──────────┐      ┌──────▼───────┐          │
        │      │ UART TX  │◄─────│   TinyECG    │          │
bot_out[0]◄────┤  Bridge  │◄─────│ (1D CNN Core)│          │
        │      └──────────┘      └──────────────┘          │
        └──────────────────────────────────────────────────┘
```

---

## [0,1] ProxCore (Proximity Safety Co-Processor)
**participant Design Connection:**
This project implements a real-time FIR filter and threshold comparator for LiDAR sensors. It uses a combination of UART for sensor data and SPI for runtime configuration.

*   **Interface:** UART (LiDAR Data) + SPI (Config)
*   **GPIO Mapping (Bottom Edge):**
    *   `gpio_bot_in[0]`: `uart_rx` (Input - LiDAR samples)
    *   `gpio_bot_in[1]`: `spi_sck` (Input)
    *   `gpio_bot_in[2]`: `spi_cs_n` (Input)
    *   `gpio_bot_in[3]`: `spi_mosi` (Input)
    *   `gpio_bot_out[4]`: `brake_irq` (Output - Interrupt)
    *   `gpio_bot_out[5]`: `dbg_filtered_valid` (Output - Debug)
*   **Reset Behavior:** The participant handles the reset by utilizing the gated `reset_n` directly for the core's `rst_n` signal. This clears the FIR filter pipeline and configuration registers.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        .rst_n(reset_n),    
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** Both `gpio_bot_oeb[4]` (brake_irq) and `gpio_bot_oeb[5]` (dbg_filtered_valid) are explicitly set to `1'b0` (Output) in the wrapper. Input signals (UART/SPI) leave their respective OEB bits at `1'b1` (Hi-Z).
    *   **Drive Mode:** Pins `[3:0]` use `3'b001` (Input). Pins `[4]` and `[5]` are configured with `3'b110` (Strong push-pull) for digital output.
    *   **Safety Note:** Unused GPIOs use DM 3'b110 with OEB set to 1 (Hi-Z) for "Safe Mode" to prevent contention and protect the SoC.

### Block Diagram:
```text
           PROJECT MACRO [0,1]
        ┌─────────────────────────────────────────────────────────┐
        │  ┌─────────┐      ┌──────────────┐      ┌──────────┐    │
bot_in[0]─►│ UART RX │─────►│  FIR Filter  ├─────►│ Threshold│    │
        │  └─────────┘      │   (Q10.6)    │      │ Comp     ├───► bot_out[4]
        │  ┌─────────┐      └──────┬───────┘      └────┬─────┘    │
bot_in[1:3]►│ SPI Slv │─────────────┘                   │          │
        │  └─────────┘             (Coefficients)      │          │
        └──────────────────────────────────────────────┘          │
```

---

## [0,2] TraceGuard-X (Anomaly Detection ASIC)
**participant Design Connection:**
This design is the most comprehensive in terms of GPIO usage, utilizing the Bottom bank for control/status and the Right bank for a parallel data bus.

*   **Bottom Edge (`gpio_bot`):**
    *   `gpio_bot_in[0]`: `uart_rx` (In) - Command/Token streaming.
    *   `gpio_bot_out[1]`: `uart_tx` (Out) - Status responses.
    *   `gpio_bot_out[2]`: `gpio_alert` (Out) - Real-time anomaly flag.
    *   `gpio_bot_out[3]`: `gpio_match` (Out) - Pattern match indicator.
    *   `gpio_bot_out[4]`: `gpio_busy` (Out) - Engine processing state.
    *   `gpio_bot_out[5]`: `gpio_ready` (Out) - Detection handshake.
    *   `gpio_bot_out[6]`: `gpio_overflow` (Out) - SRAM capacity alert.
    *   `gpio_bot_out[7]`: `gpio_wd_alert` (Out) - Watchdog timeout.
    *   `[9:8]`: `gpio_mode` (Out) - Current FSM state (Idle/Learn/Detect/Build).
*   **Right Edge (`gpio_rt`):**
    *   `gpio_rt_out[7:0]`: `gpio_score` (Out) - 8-bit parallel normalcy score.
*   **Reset Behavior:** The core utilizes the gated `reset_n` signal from the Green Macro directly for its `rst_n` input. This signal initializes the Aho-Corasick match engine, the control FSM, and the shared SRAM arbitration logic.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        .rst_n(reset_n), // Gated system reset
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** `gpio_bot_oeb` is set to `15'b11111_00_0000000_1`, explicitly configuring bit 0 as an input for UART RX, and bits 1 through 9 as outputs for status and the UART TX. The Right bank (`gpio_rt_oeb`) enables bits [7:0] as outputs for the parallel score bus.
    *   **Drive Mode:** All active pins across the Bottom and Right banks use the default `3'b110` (Strong digital push-pull) to maintain high signal integrity for the UART and high-speed parallel score bus.

### Block Diagram:
```text
           PROJECT MACRO [0,2]
        ┌─────────────────────────────────────────────────────────┐
        │  ┌─────────┐      ┌──────────────┐      ┌──────────┐    │
bot_in[0]─►│ UART RX │─────►│ CMD Decoder  ├─────►│ CTRL FSM │    │
        │  └─────────┘      └──────┬───────┘      └────┬─────┘    │
        │                          │ (Tokens)          │ (Mode)   │
        │  ┌─────────┐      ┌──────▼───────┐           │          │
bot_out[1]◄┤ uart_tx  │◄─────│  AC Engine   │◄──────────┘          │
        │  └─────────┘      │(Aho-Corasick)│          GPIO FLAGS  │
        │                   └──────┬───────┘      (bot_out[2:9]) ──►
        │        ┌────────┐        │                   ▲          │
        │        │ Shared │◄───────┘      ┌────────┐   │          │
        │        │ SRAM   │               │ Score  ├───┘          │
        │        └────────┘               │ Unit   ├────────────┐ │
        │                                 └────────┘            │ │
        └───────────────────────────────────────────────────────┼─┘
                                                                │
                                                        SCORE BUS rt_out[7:0]
```

---

## [1,0] NTT-Engine (Number Theoretic Transform Accelerator)
**Participant Design Connection:**
This project implements a hardware accelerator for the Number Theoretic Transform (NTT), a critical primitive in lattice-based cryptography. It utilizes a simplified SPI interface mapped to the Bottom GPIO bank.

*   **Interface:** SPI Slave
*   **GPIO Mapping (Bottom Edge):**
    *   `gpio_bot_in[0]`: `cs_n` (Input - Active Low)
    *   `gpio_bot_in[1]`: `mosi` (Input - Master Out Slave In)
    *   `gpio_bot_out[0]`: `miso` (Output - Master In Slave Out)
*   **Reset Behavior:** The core utilizes the gated `reset_n` signal from the Green Macro. This ensures the NTT transformation state machine and internal memory pointers are initialized only when the project is active and the system reset is deasserted.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        .rst_n(reset_n), // Gated system reset
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** `gpio_bot_oeb[0]` is explicitly driven low (`1'b0`) to enable the `miso` output. All other GPIOs (bottom, right, top) default to input mode (`oeb=1`).
    *   **Drive Mode:** Uses the default `3'b110` (Strong push-pull) for the MISO output to ensure timing closure across the orange-purple MUX tree. Input pins `[1:0]` are optimized for digital input.

### Block Diagram:
*   **GPIO Contention Issue:**
    The current mapping creates a contention on `gpio_bot[0]`, since `gpio_bot_in[0]` and `gpio_bot_out[0]` refer to the same physical pad. 
    The `cs_n` signal is intended as an input (`gpio_bot_in[0]`), while `miso` is assigned to `gpio_bot_out[0]`. In addition, `gpio_bot_oeb[0]` is set to `1'b0` (output mode), which enables the output driver.

```text
           PROJECT MACRO [1,0]
        ┌─────────────────────────────────────────────────────────┐
        │                                                         │
        │  ┌───────────┐        ┌──────────────────────────┐      │
bot_in[0]─►│           │        │                          │      │
        │  │ SPI Slave │───────►│      NTT-Engine Core     │      │
bot_in[1]─►│ Decoder   │        │   (Butterfly + Twiddle)  │      │
        │  │           │◄───────│                          │      │
        │  └─────┬─────┘        └────────────┬─────────────┘      │
        │        │                           │                    │
bot_out[0]◄──────┘               reset_n ────┘                    │
        │                                                         │
        └─────────────────────────────────────────────────────────┘
```

---

## [1,1] NeuralTram (Systolic Array)
**participant Design Connection:**
The participant opted for a standardized SPI interface to communicate with a 4x4 matrix multiplier. All connections are localized on the Top edge for easy wiring.

*   **Top Edge (`gpio_top`):**
    *   `gpio_top_in[0]`: `CS_N` (Input) - SPI Chip Select.
    *   `gpio_top_in[1]`: `SCLK` (Input) - SPI Clock.
    *   `gpio_top_in[2]`: `MOSI` (Input) - SPI Data In.
    *   `gpio_top_out[3]`: `MISO` (Output) - SPI Data Out.
*   **Reset Behavior:** The core utilizes the gated `reset_n` signal from the Green Macro directly. This signal clears both the SPI decoder (`u_spi`) and the systolic FSM within the wrapper (`u_wrapper`), ensuring the transformation state machine and memory pointers are initialized only when the project is active. On reset deassertion, the internal MUX defaults to "SPI Access" mode to facilitate data and weight loading.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        .rst_n(reset_n), // Gated system reset for SPI and Wrapper
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** `gpio_top_oeb[3]` is explicitly driven low (`1'b0`) to enable the `miso` output. Pins `gpio_top_oeb[2:0]` are tied to `1'b1` (Inputs) for the SPI bus.
    *   **Drive Mode:** All pins in the top bank utilize the default `3'b110` (Strong digital push-pull) drive mode, providing consistent timing and drive strength for the MISO signal across the chip.

### Block Diagram:
```text
           PROJECT MACRO [1,1]
        ┌──────────────────────────────────────────────────────────────┐
        │                                                              │
        │  top_in[0] (CS_N)  ──┐                                       │
        │  top_in[1] (SCLK)  ──┼──────┐                                │
        │  top_in[2] (MOSI)  ──┼──────┼──────┐                         │
        │                      ▼      ▼      ▼                         │
        │                ┌─────────────────────────┐                   │
        │                │       simple_spi        │                   │
        │                │         (u_spi)         │──────────┐        │
        │                └────┬───────────────▲────┘          │        │
        │   (addr, din, we,   │               │ (dout, busy,  │        │
        │    start, config)   │               │  done)        │        │
        │                ┌────▼───────────────┴────┐          │        │
        │                │     systolic_wrapper    │          │        │
        │                │       (u_wrapper)       │          │        │
        │                └────────────┬────────────┘          │        │
        │                             │ (4x4 Matrix Op)       │        │
        │                ┌────────────▼────────────┐          │        │
        │                │      systolic_array     │          │        │
        │                └─────────────────────────┘          │        │
        │                                                     │        │
        │  top_out[3] (MISO) ◄────────────────────────────────┘        │
        │                                                              │
        └──────────────────────────────────────────────────────────────┘
```

---

## [1,2] Cryptic (BLAKE2s Hash Accelerator)
**Participant Design Connection:**
This project implements a BLAKE2s cryptographic hash accelerator, accessed via a 4-wire SPI interface that maps to a 32-bit register file. The core performs single-block hashing.

*   **Interface:** 4-wire SPI Slave (MSB-first, 42-bit frame, CPOL=0 CPHA=0)
*   **GPIO Mapping (Bottom Edge):**
    *   `gpio_bot_in[0]`: `spi_sclk` (Input) - SPI Clock.
    *   `gpio_bot_in[1]`: `spi_cs_n` (Input) - SPI Chip Select (Active Low).
    *   `gpio_bot_in[2]`: `spi_mosi` (Input) - SPI Master Out Slave In.
    *   `gpio_bot_out[0]`: `spi_miso` (Output) - SPI Master In Slave Out.
*   **SPI Frame Format:**
    *   `Bit[41]`: `R/nW` (1=read, 0=write)
    *   `Bit[40:33]`: `address[7:0]`
    *   `Bit[32:1]`: `write_data[31:0]` (ignored on reads)
    *   `Bit[0]`: Padding bit
*   **Reset Behavior:** The core utilizes the gated `reset_n` signal from the Green Macro directly. This signal clears the internal SPI state machine and the BLAKE2s register file, ensuring a clean and predictable start for hash operations.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        .reset_n(reset_n), // Gated system reset for SPI and BLAKE2s core
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** `gpio_bot_oeb[0]` is explicitly driven low (`1'b0`) to enable the `spi_miso` output. `gpio_bot_oeb[14:1]` are tied high (`1'b1`) for unused inputs.
    *   **Drive Mode:** All GPIOs (bottom, right, and top) are configured with the default `3'b110` (Strong digital push-pull) drive mode. This ensures consistent drive strength for the MISO signal and sets a robust default for unused pins.

### Block Diagram:
*   **GPIO Contention Issue:** 
    There is a functional conflict on physical pad **`gpio_bot[0]`**. The system is configured to sample the SPI Clock (`spi_sclk`) from `gpio_bot_in[0]` while simultaneously driving the SPI Master-In-Slave-Out (`spi_miso`) signal via `gpio_bot_out[0]`. 
    Since `gpio_bot_oeb[0]` is set to `1'b0` (Output Mode), the internal MISO driver will conflict with the external Clock signal provided by the SPI Master. This contention will likely cause signal integrity failure and prevent the SPI state machine from sampling the clock correctly.

*Note: `reset_n` is the gated system reset.*

```text
           PROJECT MACRO [1,2]
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
bot_in[0] (SCLK)  ──┐                                             │
bot_in[1] (CS_N)  ──┼──────┐                                      │
bot_in[2] (MOSI)  ──┼──────┼──────┐                               │
        │           ▼      ▼      ▼                               │
        │     ┌─────────────────────────┐                         │
        │     │   SPI-to-Regfile Bridge │                         │
        │     │   (42-bit frame)        │──────────┐              │
        │     └────┬───────────────▲────┘          │              │
        │          │ (cs, we, addr,│ (rdata)       │              │
        │          │  wdata)      │                │              │
        │     ┌────▼───────────────┴────┐          │              │
        │     │     blake2s_regs        │          │              │
        │     │ (BLAKE2s Hash Core)     │          │              │
        │     └────────────┬────────────┘          │              │
        │                  │ reset_n               │              │
        │                  └───────────────────────┘              │
        │                                                         │
bot_out[0] (MISO) ◄───────────────────────────────────────────────┘
        └──────────────────────────────────────────────────────────┘
```

---

## [2,0] XtraRandom (Stochastic Entropy Primitive)
**participant Design Connection:**
A True Random Number Generator (TRNG) utilizing thermal jitter to produce a multi-bit stochastic stream. The design is protocol-less and configured for continuous operation.

*   **Communication Interface:** Clock-driven synchronous (Protocol-Less).
*   **GPIO Mapping (Bottom Edge):**
    *   `gpio_bot_out[0]`: `q1` (Output) - Entropy bit 0.
    *   `gpio_bot_out[1]`: `q2` (Output) - Entropy bit 1.
    *   `gpio_bot_out[2]`: `q3` (Output) - Entropy bit 2.
*   **Reset Behavior:** In the current RTL implementation, the TRNG core is "always ON" (`en=1'b1`) and does not utilize the gated `reset_n` or `por_n` signals for its internal logic.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        wire en = 1'b1; // Always enabled
        u_trng (.clk(clk), .en(en), ...);
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** `gpio_bot_oeb[2:0]` is tied to `3'b000` to enable outputs for all three entropy bits. All other bottom GPIOs are set to high-impedance.
    *   **Drive Mode:** All active outputs use the default `3'b110` (Strong digital push-pull) to ensure clear signal transitions and maintain the stochastic integrity of the jitter source.

### Block Diagram:
```text
           PROJECT MACRO [2,0]
        ┌──────────────────────────────────────────────────────────────┐
        │                                                              │
        │                        ┌──────────────────┐                  │
        │                        │     trng_top     │                  │
        │                        │     (u_trng)     │                  │
  CLK ──┼───────────────────────►│                  ├───► bot_out[0] (q1)
        │                        │                  ├───► bot_out[1] (q2)
        │         1'b1 (en) ────►│                  ├───► bot_out[2] (q3)
        │                        └──────────────────┘                  │
        │                                                              │
        └──────────────────────────────────────────────────────────────┘
```

---

## [2,1] I2C-UART Controller (Dual-I2C Bridge)
**Participant Design Connection:**
This project provides a versatile communication bridge featuring an I2C Master for controlling external sensors and an I2C Slave (factory set to Address `0x55`) for interface with a host controller. It also includes a UART transmitter for telemetry output.

*   **Interface:** I2C (Master & Slave) + UART (TX Only)
*   **GPIO Mapping (Top Edge):**
    *   `gpio_top_in/out[0]`: `mst_scl` (Inout)
    *   `gpio_top_in/out[1]`: `mst_sda` (Inout)
    *   `gpio_top_in[2]`: `slv_scl` (Input Only)
    *   `gpio_top_in/out[3]`: `slv_sda` (Inout)
    *   `gpio_top_out[4]`: `uart_tx` (Output)
*   **Reset Behavior:** The module is initialized using the gated `reset_n` signal. This ensures that the I2C state machines and the UART baud rate generator are held in reset until the project slot is enabled via the scan chain.
    *   **Code Snippet (from `project_macro.v`):**
        ```verilog
        .rst_n(reset_n), // Gated system reset
        ```
*   **Drive Modes & OEB Control:**
    *   **OEB:** The `mst_scl_t`, `mst_sda_t`, and `slv_sda_t` signals dynamically control the output enables for I2C bi-directionality. `gpio_top_oeb[4]` is tied to `1'b0` for the UART TX output.
    *   **Drive Mode:** All pins utilize the default `3'b110` (Strong digital push-pull).

### Block Diagram:
```text
           PROJECT MACRO [2,1]
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
        │  ┌────────────┐        ┌──────────────┐                  │
top[0:1]◄─►│ I2C Master │◄──────►│              │                  │
        │  └────────────┘        │              │                  │
        │  ┌────────────┐        │   chip_top   │      ┌────────┐  │
top[2:3]◄─►│ I2C Slave  │◄──────►│              ├─────►│UART TX ├──► top[4]
        │  │ (Addr 0x55)│        │              │      └────────┘  │
        │  └────────────┘        └──────────────┘                  │
        │                                                          │
        └──────────────────────────────────────────────────────────┘
```

---

## Summary Table for Integration

| Project Slot | Logic Type | Primary Bank | Communication | Key Feature |
| :--- | :--- | :--- | :--- | :--- |
| **[0,0]** | 1D CNN | Bottom | UART | ECG Arrhythmia Classifier |
| **[0,1]** | FIR Filter | Bottom | UART + SPI | Proximity Safety Co-Processor |
| **[0,2]** | Aho-Corasick | Bottom + Right | UART + Parallel | Anomaly Detection ASIC |
| **[1,0]** | NTT Engine | Bottom | SPI Slave | Lattice-Based Cryptography |
| **[1,1]** | Systolic Array | Top | SPI Slave | INT8 Matrix Multiplier |
| **[1,2]** | BLAKE2s Hash | Bottom | SPI Slave | Cryptographic Accelerator |
| **[2,0]** | TRNG | Bottom | Protocol-Less | Stochastic Entropy Primitive |
| **[2,1]** | I2C Bridge | Top | I2C + UART | Dual-I2C Controller |