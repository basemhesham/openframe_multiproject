# Hardware Accelerator for Number Theoretic Transform (NTT) 

## Project Overview
The emergence of quantum computing threatens classical cryptographic systems such as RSA and ECC [cite: 1]. To address this, the National Institute of Standards and Technology (NIST) has standardized post-quantum algorithms like CRYSTALS-Kyber, which rely on hard mathematical problems such as Learning With Errors. 

These algorithms depend heavily on polynomial arithmetic, making them computationally intensive for general-purpose processors. A key component is the Number Theoretic Transform (NTT), which accelerates polynomial multiplication and reduces complexity from quadratic $\mathcal{O}(n^2)$ to quasi-linear $\mathcal{O}(n \log n)$, enabling the practical implementation of PQC systems.

In this project, we design a hardware accelerator for NTT as the core engine of post-quantum cryptography. The design is implemented using RTL and mapped through a full ASIC flow using open-source tools, from synthesis to GDSII generation. This work bridges advanced cryptographic theory with efficient hardware design.
## NTT/INTT architecture
![architecture](assets/NTT_Architecture.png)
## Interface (SPI) 
![architecture](assets/SPI.png)

## Architecture Highlights
The core of this accelerator is based on an efficient Number Theoretic Transform architecture optimized for CRYSTALS-Kyber. 
* **Unified Butterfly Unit (UBU):** The design features a novel Unified Butterfly Unit (UBU) developed by combining interleaved multiplication, radix-4, and resource-sharing strategies. 
* **NTT & INTT Support:** The UBU computes all butterfly operations required for both the Forward NTT (Cooley-Tukey Butterfly) and the Inverse NTT (Gentleman-Sande Butterfly), eliminating the need for separate hardware.
* **CRYSTALS-Kyber Parameters:** The architecture is configured for the Kyber parameters, specifically supporting a polynomial degree of $N=256$ and the prime modulus $q=3329$.
* **SPI Interface:** Built-in SPI slave module for seamless external configuration, data loading, and retrieving results.
* **Caravel SoC Integration:** Wrapped in a `project_macro` utilizing the Sky130 OpenFrame GPIO Pad Modes to interface with the Caravel harness.

## Module Descriptions
* `NTT_Top_Wrapper.v`: The top-level wrapper module that interfaces the SPI bus with the NTT Core and exposes external RAM access.
* `NTT_Accelerator_Top.v`: The core accelerator instantiating the RAM, ROM, Control Unit, and the Unified Butterfly Unit.
* `U_Butterfly_Unit.v`: The unified computational engine performing modular multiplication, addition, and subtraction utilizing the Interleaved Multiplication (IM) approach.
* `NTT_Control_Unit.v`: State machine orchestrating the memory reads, UBU execution phases, and writes across the $O(n \log n)$ pipeline.
* `NTT_RAM.v`: A generic dual-port Block RAM implementation to store intermediate polynomial coefficients.
* `Twiddle_ROM.v`: Stores the pre-computed twiddle factors (powers of $\omega$) required for the 256-point NTT over the modulus $q=3329$.
* `SPI_Slave.v`: Synchronous SPI interface handling command decoding and memory addressing.

## Active Pin Mapping (NTT Core to Caravel SoC)
These are the pins actively used by the NTT top wrapper and their physical routing to the Sky130 Caravel harness:

| Logical Signal (NTT Core) | Direction | Physical Macro Pin | Edge Location | Description |
| :--- | :--- | :--- | :--- | :--- |
| `clk` | Input | `clk` | Left | Core Clock / Green Macro | System clock signal |
| `rst_n` | Input | `reset_n` | Left | Core Reset / Green Macro | Active-low system reset |
| `cs_n` | Input | `gpio_bot_in[0]` | Bottom |SPI Chip Select (Active Low) |
| `mosi` | Input | `gpio_bot_in[1]` | Bottom |SPI Master Out Slave In |
| `miso` | Output | `gpio_bot_out[0]` | Bottom |SPI Master In Slave Out |




## Sky130 ASIC Implementation Details
**Suitability for Sky130 Process:**
* Fully digital design, requiring no analog complexity.
* Area-efficient footprint (~ 1 ${mm}^2$).
* Standard cell compatible with a simple open-source synthesis flow (OpenLANE/OpenROAD).

## Team Members
* Ahmed Ibrahim
* Ahmed Khalaf

## References
* [1] K. Javeed and D. Gregg, "Efficient Number Theoretic Transform Architecture for CRYSTALS-Kyber," IEEE Transactions on Circuits and Systems-II: Express Briefs, vol. 72, no. 1, pp. 263-267, January 2025.


