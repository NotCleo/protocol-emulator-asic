# protocol-emulator-asic


### Sept 14 2026 (Monday) 

    Read about the process kit (ihp-sg13cmos5l) : IHP's 130 nm CMOS/BiCMOS process (SG13S and SG13G2) features a stack with 5 thin and 2 thick metal layers 
    [1] (https://github.com/IHP-GmbH/IHP-Open-PDK)
    [2] (https://www.ihp-microelectronics.com/services/research-and-prototyping-service/mpw-prototyping-service/sigec-bicmos-technologies)
    [3] (https://github.com/IHP-GmbH/ihp-sg13cmos5l) 
    
    Key Specifications : 
    Node & Gate Length: 130 nm (0.13 µm) CMOS with high-performance SiGe:C npn-HBTs available in related nodes.
    Metal Stack: 5 thin metal layers and 2 thick metal layers (5L configuration). 
    Supply Voltages: 1.2 V core voltage (thin gate oxide) and 3.3 V high-voltage I/O (thick gate oxide). 
    Operating Range: -40°C to +125°C.

    Read about memory macro selection : https://tinytapeout.com/specs/memory/
    
    Found out around 26 IO pads is the limit : https://tinytapeout.com/specs/gpio/ 
    
    Summary Rule of Thumb

    Design the instruction (ISA opcodes) fields and width to meet your protocol bit-banging needs first, then pick an instruction word size (like 16-bit or 32-bit)

### Sept 17 2026 (Thursday) 

    RP2040's PIO was really cool
    Came across https://github.com/raspberrypi/pico-examples/tree/master/pio
    Watch : https://www.youtube.com/watch?v=yYnQYF_Xa8g&t=75s
    Basically We now have the following changes : 

        An 6x4 allocation is 24 tiles. At approximately 200um × 150um per tile, that’s about 0.7 mm² of nominal tile area. As a rough estimate, budget for about 1K logic cells per tile.

        To ensure routability and non-std cell/clock tree synth, we need to close our design at around 16k logic cells (inclusive of the SRAM Macro), leaving remaining 8k cells 

    We have an assorted set of tools to work with;

        PDK	IHP-Open-PDK (sg13g2)
        RTL → GDS	LibreLane (Yosys + OpenROAD + KLayout/Magic), driven by TT's tt-support-tools for local hardening
        Simulation	Icarus (the template default) and Verilator (fast, for long random tests)
        Testbench	cocotb (the template default). For UVM-style work use pyuvm on cocotb. Verilator 5 has partial SV/UVM support, but open-source UVM is still rough.
        Formal	SymbiYosys + SVA (FIFOs, pin-mux one-hot, decoder, no-X on outputs)

    Our true starting point is https://github.com/TinyTapeout/ttihp-verilog-template


### Sept 19 2026 (Saturday) 

    We came to an understanding that, we need to fix a protocol between the host and our emulator, mostly going to be a JTAG(USB)
    
    We are assuming that the host knows what protocol the devices work on beforehand, unless there is a protocol sensing logic?
    
    Flow : Host <-> our emulator <-> different devices using different protocols (R/W both)
    
    We realize it is a SISO/SIMO setup
    
    we produced a CDC study tree for clock domains, that we may face : 
    
    slow to fast, single bit, comb to comb 
    slow to fast, single bit, comb to seq
    slow to fast, single bit, seq to seq 
    slow to fast, single bit, seq to comb
    
    slow to fast, multi bit, comb to comb 
    slow to fast, multi bit, comb to seq
    slow to fast, multi bit, seq to seq 
    slow to fast, multi bit, seq to comb
    
    slow to fast, single bit, comb to comb 
    slow to fast, single bit, comb to seq
    slow to fast, single bit, seq to seq 
    slow to fast, single bit, seq to comb
    
    fast to slow, multi bit, comb to comb 
    fast to slow, multi bit, comb to seq
    fast to slow, multi bit, seq to seq 
    fast to slow, multi bit, seq to comb
    
    fast to slow, single bit, comb to comb 
    fast to slow, single bit, comb to seq
    fast to slow, single bit, seq to seq 
    fast to slow, single bit, seq to comb
    
    slow to fast, multi bit, comb to comb 
    slow to fast, multi bit, comb to seq
    slow to fast, multi bit, seq to seq 
    slow to fast, multi bit, seq to comb
    
    We need to fix our ISA width to decide SRAM Macro usage
    
    We need to look into the FSM implementation 
    
    We think we need an ISA for initial handshake for programming our emulator
    
    A bare idea we made up is as follows:
    
    Host initiates the emulator with the ISA and then sends an INT, which our IRQ acks and initiates the protocol it needs and relays back the device's packets through the USB? (we are not sure how to streamline the data flow)




