# NTP Server based on GPS disciplined OCXO

* [MicroZed](http://zedboard.org/product/microzed) processor board
* Xilinx Zynq 7010 ARM processor/fpga
* STRATUM 3E High Stability Oven Stabilized Oscillator
* GlobalTop LadyBird-1 GPS Receiver
* 18 Digit non-multiplexed time/info display
* 1U case 4 inches deep

## Directory layout
* boot

  Files in the boot partition that the Zynq uses for bootstrap loading.
* fpga (submodule)

  The FPGA code for the Zynq processor.  Setup for the v1.1.0 version of the main board.  The FPGA drives the custom peripherals on the main board:
  - Time Stamp Counter (TSC) running from the OCXO clock.
  - Multi digit 7-segment display.
  - OCXO control voltage DAC.
  - Phase detector between GPS PPS signal and OCXO PPS signal.
  - Time of day counters.
* freecad (submodule)

  freecad 1.0 3D models for the case parts and components for kicad.
  * case

    3D model of the case, display, pcb, power supply, etc
    * airduct

      Cover mounted fan and air duct to redirect air flow horizontally.
    * assembly.FCStd

      Top level case assembly incorporating all other files in this directory
    * filter

      Front filter models with experimental mounting to the front panel.
  * ponoko

    File sent to [ponoko](https://www.ponoko.com/) to make the OXCO cover, air duct for the fan, red acrylic filter for the display, and experimental parts for the case.
* kicad (submodule)
  * 2x7seg

    2 Digit 7-segment display board.  Designed to be strung together to any length.
  * clock

    The mainboard for the clock.
  * rj45brkout

    Break out board for the panel mount RJ45 Ethernet connector.
  * term

    The termination and connector board.  Used at both ends of the display string.
  * usbabrkout

    Break out board for the panel mount USB-A connector.
  * usbbbrkout

    Break out board for the panel mount USB-B connector.
* linux (submodule)

  Submodule pointing to the Xilinx version of linux used.
* u-boot (submodule)

  Submodule pointing to the Xilinx version of u-boot used.
* scripts

  Various test scripts and programs to setup the programmed FPGA.
  * clocksource

    A simple clockdource driver to use the OCXO TSC as the timekeeping source.

  * pps

    A simple PPS driver for the OCXO PPS generator that is compatible with the ntp deamon.


Case
![case](./image/case.png)

Main PCB
![main](./image/mainpcb.png)

Display
![disp](./image/disp.png)


