welcome to truffle qa
all scripts are in /scripts
stage0
script that will run on first boot prepping sytem for qa 
stage 1 and stage 2
are triggered by a python cli (later a nice front end)
logs are scped over to the host linux pc
where the oython cli lives
/linux_pc contains the setup that needs to be on the linux pc
truffle-xxxx specific dire is made in truffle_QA
with logs of each stage which are later analyzed by an LLm and stored in a db!

more to come but enjoy
this was fun

ok new update this is much better now
has proper bacend lol
no ssh shit
stillhave to implement woprker on a different pc to connect to hotspot
initials etup

# On the Jetson device:
cd /home/truffle/qa

# Install dependencies
sudo ./src/preflash.sh

# Install systemd service
sudo ./install_service.sh

start service

# Start testing now
sudo systemctl start qa-test

# Stop testing
sudo systemctl stop qa-test

# Check status
sudo systemctl status qa-test

# View live logs
sudo journalctl -u qa-test -f
