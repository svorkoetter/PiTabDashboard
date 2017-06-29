PiTabDashboard is a graphical utility to display the current state of a
Raspberry Pi based tablet, as described here
(http://www.stefanv.com/electronics/a-compact-home-made-raspberry-pi-tablet.html),
and to allow the user to change some power management settings:

* displays system status:
    * battery voltage
    * estimated energy remaining
    * CPU/GPU temperature
    
* lets user adjust power saving settings:
    * dim display when idle on battery power
    * enable external USB and audio (and the unused Ethernet port)
    * enable Wi-Fi and Bluetooth
    
* displays concise information in its taskbar icon:
    * energy remaining both as a gauge and a number
    * gauge blinks at 2Hz when energy is below 5%
    * blinking lightning bolt at 1Hz indicates charging is in progress
    * solid lightning bolt indicates charging is complete

PiTabDashboard is intended to be used together with PiTabDaemon
(https://github.com/svorkoetter/PiTabDaemon).
