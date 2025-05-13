#!/usr/bin/python3
#
# TWO-STAGE THERMAL TEST: 
# STAGE 0: WITHOUT LEDS
# STAGE 1: WITH LEDS
#

import csv
import time
import os
import argparse
from datetime import datetime
from jtop import jtop
import subprocess
import sys
import signal

# Parse command line arguments
parser = argparse.ArgumentParser(description='Two-stage thermal test with LED control')
parser.add_argument('--stage-one', type=float, default=2.0,
                    help='Duration of stage one (without LEDs) in hours (default: 2.0)')
parser.add_argument('--stage-two', type=float, default=2.0,
                    help='Duration of stage two (with LEDs) in hours (default: 2.0)')
args = parser.parse_args()

# Convert hours to seconds
STAGE_ONE_DURATION = int(args.stage_one * 3600)  # Convert hours to seconds
STAGE_TWO_DURATION = int(args.stage_two * 3600)  # Convert hours to seconds
TOTAL_DURATION = STAGE_ONE_DURATION + STAGE_TWO_DURATION

# How often to write data to CSV file (seconds)
LOG_INTERVAL = 5

# Get the directory containing the script
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Change to the script's directory to ensure all relative paths work
os.chdir(SCRIPT_DIR)

print(f"TWO-STAGE THERMAL TEST")
print(f"STAGE 0: {args.stage_one:.1f} hours WITHOUT LEDs")
print(f"STAGE 1: {args.stage_two:.1f} hours WITH LEDs")
print(f"LOGGING TO CSV EVERY {LOG_INTERVAL} SECONDS")

benchmark_processes = None

# Define commands for stress tools
gpu_stress_command = ["/home/truffle/qa/THERMALTEST/gpu_burn", "-m", "85%", str(TOTAL_DURATION + 60)]
cpu_stress_command = ["/usr/bin/stress", "-c", "8", "-t", str(TOTAL_DURATION + 60)]
led_stress_command = ["/home/truffle/led_renderer_og/led_white"]
led_off_command = ["sudo", "/home/truffle/led_renderer_og/ledoff"]

def _start(cmd):
    # Each tool gets its own process-group so we can kill children cleanly
    return subprocess.Popen(cmd, preexec_fn=os.setsid)

def start_cpu_gpu_benchmark():
    print("Starting CPU and GPU stress...")
    return [
        _start(gpu_stress_command),
        _start(cpu_stress_command),
    ]

def start_led_benchmark():
    print("Starting LED stress...")
    return _start(led_stress_command)

def turn_off_leds():
    print("Turning off LEDs...")
    try:
        subprocess.run(led_off_command, check=True)
        print("LEDs turned off successfully")
    except subprocess.CalledProcessError as e:
        print(f"Failed to turn off LEDs: {e}")
    except FileNotFoundError:
        print("LED off command not found. Make sure /home/truffle/led_renderer_og/ledoff exists")

def stop_benchmark():
    global benchmark_processes
    if benchmark_processes:
        print("Killing benchmark tools...")
        for p in benchmark_processes:
            if p is not None:
                try:
                    os.killpg(os.getpgid(p.pid), signal.SIGTERM)   # whole group
                except ProcessLookupError:
                    pass
        print("Waiting for benchmark tools to end...")
        for p in benchmark_processes:
            if p is not None:
                p.wait()
        print("All load generators stopped")

# Function to handle SIGINT (Ctrl+C)
def signal_handler(sig, frame):
    print("\nSIGINT received, cleaning up...")
    stop_benchmark()  # Stop the benchmark process
    turn_off_leds()   # Make sure LEDs are off
    sys.exit(0)       # Exit the program

signal.signal(signal.SIGINT, signal_handler)

# Create a fixed filename for the CSV log (no timestamp)
csv_filename = "/home/truffle/qa/scripts/logs/stage2_burn_log.csv"
print(f"SAVING TO {csv_filename}")

# Create logs directory if it doesn't exist
os.makedirs("/home/truffle/qa/scripts/logs", exist_ok=True)

# Start the CPU and GPU benchmarks
benchmark_processes = start_cpu_gpu_benchmark()
led_process = None

# Make sure LEDs are off at the beginning
turn_off_leds()

# Open CSV file for writing
with open(csv_filename, mode='w', newline='') as csvfile:
    fieldnames = ['time', 'stage', 'Temp CPU', 'Temp GPU', 'Temp SOC0', 'Temp SOC1', 'Temp SOC2', 
                  'Temp Tboard', 'Temp Tdiode', 'Temp tj', 'Power TOT', 'RAM', 'CPU1', 
                  'CPU2', 'CPU3', 'CPU4', 'CPU5', 'CPU6', 'CPU7', 'CPU8', 'GPU', 'Fan pwmfan0']
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

    # Write header to CSV
    writer.writeheader()

    start_time = time.time()
    last_update_time = time.time()
    current_stage = 0

    # Use jtop to monitor the Jetson stats
    with jtop() as jetson:
        while jetson.ok():
            current_time = time.time()
            elapsed_time = current_time - start_time
            
            # Check if we need to switch to stage 1
            if current_stage == 0 and elapsed_time >= STAGE_ONE_DURATION:
                print(f"\n--- SWITCHING TO STAGE 1: WITH LEDS ---")
                current_stage = 1
                led_process = start_led_benchmark()
                if led_process:
                    benchmark_processes.append(led_process)
            
            # Check if test is complete
            if elapsed_time >= TOTAL_DURATION:
                break
            
            # Get stats from jetson
            stats = jetson.stats
            
            # Log the data with stage information
            row = {
                'time': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                'stage': current_stage,  # 0 = without LEDs, 1 = with LEDs
                'Temp CPU': stats.get('Temp CPU', None),
                'Temp GPU': stats.get('Temp GPU', None),
                'Temp SOC0': stats.get('Temp SOC0', None),
                'Temp SOC1': stats.get('Temp SOC1', None),
                'Temp SOC2': stats.get('Temp SOC2', None),
                'Temp Tboard': stats.get('Temp Tboard', None),
                'Temp Tdiode': stats.get('Temp Tdiode', None),
                'Temp tj': stats.get('Temp tj', None),
                'Power TOT': stats.get('Power TOT', None),
                'RAM': stats.get('RAM', None),
                'CPU1': stats.get('CPU1', None),
                'CPU2': stats.get('CPU2', None),
                'CPU3': stats.get('CPU3', None),
                'CPU4': stats.get('CPU4', None),
                'CPU5': stats.get('CPU5', None),
                'CPU6': stats.get('CPU6', None),
                'CPU7': stats.get('CPU7', None),
                'CPU8': stats.get('CPU8', None),
                'GPU': stats.get('GPU', None), 
                'Fan pwmfan0': stats.get('Fan pwmfan0', None)
            }

            # Write the data row to the CSV file
            writer.writerow(row)
            # Make sure to flush to disk so the file is always up to date
            csvfile.flush()

            # Sleep to control logging frequency
            time.sleep(LOG_INTERVAL)
            
            # Periodic status updates
            if current_time - last_update_time > 300:  # Update every 5 minutes
                last_update_time = current_time
                hours_elapsed = elapsed_time / 3600
                hours_total = TOTAL_DURATION / 3600
                stage_name = "WITHOUT LEDs" if current_stage == 0 else "WITH LEDs"
                print(f"\nStatus: STAGE {current_stage} ({stage_name})")
                print(f"Time elapsed: {hours_elapsed:.2f} hours / {hours_total:.2f} hours total")
                print(f"Junction temp: {stats.get('Temp tj', 'N/A')}°C, Fan: {stats.get('Fan pwmfan0', 'N/A')}%")

print("\nTest completed!")
print(f"Saved CSV file to {csv_filename}")
print("Stopping stress tools...")

# Stop all benchmarks
stop_benchmark()

# Make sure LEDs are off at the end
turn_off_leds()

print("Test finished successfully.")
