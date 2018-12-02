# FIR-filter RTL files
Neural signal DSP project- only RTL files

This circuit takes in small input voltage signals, runs it through an ADC, then a Finite Impulse Response Filter (4 tap delay line using Daubechies 4 filter).  

The logic then compares the output values to a threshold voltage, and if it exceeds the threshold, output LEDs will light up.

Additionally, there is a security key value one must shift in through JTAG pins in order for ADC to run.
