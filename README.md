# FIR-filter RTL files
Neural signal DSP project- 

INCOMPLETE-need to fix and update with full project


This circuit should take in small input voltage signals and runs them through an ADC when I2C command sends a "GO". 

The samples are then run through a Finite Impulse Response Filter (4 tap delay line using Daubechies 4 filter).  

The logic then compares the output to a threshold voltage, and if it exceeds the threshold, output LEDs will light up.

Additionally, there is a security key value one must shift in through JTAG pins in order for ADC to run.



