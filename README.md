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
