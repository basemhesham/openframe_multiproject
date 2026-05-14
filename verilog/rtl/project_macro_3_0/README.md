# **XtraRandom: Sky130 Stochastic Entropy Primitive**

## **Overview**

XtraRandom is a hardware-level **True Random Number Generator (TRNG)** macro-module designed for the Sky130 process node. Unlike algorithmic pseudo-random generators, XtraRandom harvests atomic-level **Thermal Jitter** and **Silicon Race Hazards** to produce high-entropy nonces for safety-critical applications, specifically optimized for **V2V (Vehicle-to-Vehicle) communication**.

## **Key Features**

* **Stochastic Core**: Leverages the unpredictable nature of electron flow and gate switching delays.  
* **Monolithic Integration**: A synthesizable ASIC macro designed to be embedded directly into larger SoCs, eliminating the need for expensive external FPGA components.  
* **Hardened Logic**: Utilizes a custom-braided XOR architecture to amplify microscopic signal instabilities.  
* **Low-Power Design**: Optimized for edge devices with limited power budgets and physical space.

---

## **Technical Specifications**

| Parameter | Specification |
| :---- | :---- |
| **Process Node** | Sky130 (130nm CMOS) |
| **Entropy Sources** | Thermal Jitter & Internal Race Hazards |
| **Core Components** | HCCLG (Braided XOR) & B-XOR-LG (Feedback loops) |
| **Interface** | Clock-Driven Synchronous (Protocol-Less) |
| **Target Application** | V2V / IoT Root of Trust |

---

## **Entropy Architecture**

The XtraRandom module capitalizes on the stochastic link between physics and digital logic through two primary mechanisms:

1. **Thermal Jitter (HCCLG)**: The braided XOR circuit is designed to feed off intrinsic delays in traditional gates. These intertwined connections amplify natural jitter by extending signal paths, creating a versatile and unpredictable range of delays.  
2. **Race Hazards (B-XOR-LG)**: This secondary module uses active feedback loops to induce race conditions between incoming signals. By forcing the hardware into a state where the "winner" of a signal race is determined by atomic-level noise, the output becomes logically unpredictable.

---

## **Integration & Synthesis Requirements**

To preserve the physical sources of entropy, the toolchain must be prevented from "stabilizing" the design. The following **OpenLane** configurations are required during synthesis to bypass deterministic optimization:

* **RUN\_POST\_CTS\_RESIZER**: Set to **OFF** to prevent smoothing of signal edges.  
* **DESIGN\_REPAIR\_BUFFER\_INPUT\_PORTS**: Set to **OFF** to avoid neutralizing engineered race hazards.  
* **PL\_TARGET\_DENSITY**: Kept low to allow for optimal, uncompressed routing paths.  
* **dont\_touch**: Enforced on the Entropy Core to block any logic-level "repairs".

---

## **Post-Tapeout Validation Strategy**

The system is architected as a research-focused **Entropy Primitive**, separating physical generation (ASIC) from digital conditioning (FPGA).

### **1\. ASIC Role (Entropy Source)**

The ASIC implements only the minimal structure required to harvest entropy: the TRNG core and a small D-Flip-Flop (DFF) sampler.

* **Minimal Area**: Simple design with few standard cells to reduce footprint.  
* **Raw Output**: Produces physically random, asynchronous signals converted to a synchronous domain via the sampler.

### **2\. Protocol-Less Interface**

A communication protocol (UART/SPI) is omitted to prioritize hardware simplicity and evaluation clarity.

* **Clock-Driven**: The FPGA provides the clock to the ASIC, ensuring all outputs are synchronized for easy capture.  
* **Deterministic Readout**: The FPGA samples output pins directly every cycle, requiring no framing or serialization.

### **3\. FPGA Role (Post-Processing)**

Final conditioning and evaluation are performed off-chip.

* **Conditioning**: Bias removal (Von Neumann) and correlation reduction are handled on the FPGA.  
* **Analysis**: Statistical evaluation and entropy estimation are conducted externally to allow for testing multiple techniques without silicon redesign.

---

## **Verification Framework**

The design’s integrity is defended through a **4-Block Verification Framework**:

* **Empirical Foundation**: Establishing the existence of jitter in 130nm silicon.  
* **Neutralization of Shields**: Proving that disabling standard repairs allows entropy to surface.  
* **Mechanical Rawness**: Utilizing low-drive gates to ensure maximum sensitivity to noise.  
* **Resonance Proof**: Verifying that the circuit amplifies small artificial perturbations, proving it is ready for physical harvesting.

