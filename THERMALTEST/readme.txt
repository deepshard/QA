hello nextPCB from Los Angeles! We appreciate you!

Use the script TEST.py in /root/THERMALTEST to run a test for a duration specified at the top of the script
it will save a CSV file of all data. this is a fairly aggressive stress test and will be worse conditions than production enviroment.

for general monitoring, use the command "jtop" 
you can control the fan as well with it, really the fan can/should run at 100% for full loads, and the curve could be more aggressive, which we plan to do in the production firmware. 
NVIDIA recommends temps under 80C for sustained lifetime. once we hit these, we can compromise on volume vs temperature. 

let us know if we can help in anyway with setup or testing methods! 

thank you!! - the truffle team

ps. the "nmcli" command is the best way to get this thing working on wifi, 
    and it should have the mDNS hostname "test-truffle.local" so you don't have to use the IP address, ssh is on


username: root
password: runescape

 
