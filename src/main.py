#!/usr/bin/env python3

import os
import subprocess
import sys
import threading
import time
from pathlib import Path
from datetime import datetime

#qa starts heres

#log fille
LOG_DIR = "/home/truffle/qa_logs"

#stage 0

#all the setup and services
#WE WILL CALL STAGE0.SH with its file path /home/truffle/qa_logs/stage0.logs

#stage1
#leds, we will call leds.sh

def setup_logging():
    """Create log directory structure"""
    os.makedirs(LOG_DIR, exist_ok=True)
    print(f"Log directory set up at: {LOG_DIR}")

def run_script_with_logging(script_path, log_filename, script_args=None, script_type="bash"):
    """Run a script and capture its output to a log file"""
    log_path = os.path.join(LOG_DIR, log_filename)
    script_abs_path = os.path.abspath(script_path)
    
    if not os.path.exists(script_abs_path):
        print(f"Error: Script {script_abs_path} not found")
        return False
    
    print(f"Running {script_abs_path} -> {log_path}")
    
    try:
        with open(log_path, 'w') as log_file:
            log_file.write(f"=== {log_filename} - Started at {datetime.now()} ===\n")
            
            # Set LOG_FILE environment variable for the script
            env = os.environ.copy()
            env['LOG_FILE'] = log_path
            
            # Build command based on script type
            if script_type == "python":
                cmd = ['sudo', 'python3', script_abs_path]
            else:
                cmd = ['sudo', 'bash', script_abs_path]
            
            # Add arguments if provided
            if script_args:
                cmd.extend(script_args)
            
            result = subprocess.run(
                cmd,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                env=env,
                text=True
            )
            
            log_file.write(f"\n=== Completed at {datetime.now()} with exit code {result.returncode} ===\n")
            
        if result.returncode == 0:
            print(f"✅ {script_path} completed successfully")
            return True
        else:
            print(f"❌ {script_path} failed with exit code {result.returncode}")
            return False
            
    except Exception as e:
        print(f"❌ Error running {script_path}: {e}")
        return False

def run_parallel_tests(test_configs):
    """Run multiple tests in parallel and return results"""
    threads = []
    results = {}
    
    def run_test_thread(config):
        name = config['name']
        script_path = config['script_path']
        log_filename = config['log_filename']
        script_args = config.get('script_args', None)
        script_type = config.get('script_type', 'bash')
        
        print(f"Starting {name} in parallel...")
        success = run_script_with_logging(script_path, log_filename, script_args, script_type)
        results[name] = success
        status = "✅ completed" if success else "❌ failed"
        print(f"{name} {status}")
    
    # Start all tests in parallel
    for config in test_configs:
        thread = threading.Thread(target=run_test_thread, args=(config,))
        thread.start()
        threads.append(thread)
        time.sleep(2)  # Small delay between starts
    
    # Wait for all tests to complete
    for thread in threads:
        thread.join()
    
    return results

def main():
    print("=== QA Test Suite Starting ===")
    
    setup_logging()
    
    # Stage 0: System setup and configuration
    print("\n--- Stage 0: System Setup ---")
    success = run_script_with_logging("src/stage0.sh", "stage0_logs.txt")
    
    if not success:
        print("❌ Stage 0 failed, stopping test suite")
        sys.exit(1)
    
    # Stage 1: LED Test
    print("\n--- Stage 1: LED Test ---")
    success = run_script_with_logging("src/led_test.sh", "led_test.txt")
    
    if not success:
        print("❌ LED test failed, stopping test suite")
        sys.exit(1)
    
    # Stage 2: NVME Test
    print("\n--- Stage 2: NVME Test ---")
    success = run_script_with_logging("src/nvme_test.sh", "nvme_test.txt")
    
    if not success:
        print("❌ NVME test failed, stopping test suite")
        sys.exit(1)
    
    # Stage 3: Hotspot Test
    print("\n--- Stage 3: Hotspot Test ---")
    success = run_script_with_logging("src/hotspot_test.sh", "hotspot_test.txt")
    
    if not success:
        print("❌ Hotspot test failed, stopping test suite")
        sys.exit(1)
    
    # Stage 4: GPU Burn Test
    print("\n--- Stage 4: GPU Burn Test ---")
    burn_args = ["--stage-one", "2", "--stage-two", "2"]
    success = run_script_with_logging("src/burn_test.sh", "burn_test.txt", burn_args, "python")
    
    if not success:
        print("❌ GPU burn test failed, stopping test suite")
        sys.exit(1)
    
    # Stage 5: Parallel Stress Test (GPU + NVME + Hotspot)
    print("\n--- Stage 5: Parallel Stress Test ---")
    print("Running GPU burn test, NVME test, and hotspot test simultaneously...")
    
    parallel_configs = [
        {
            'name': 'GPU Burn Test',
            'script_path': 'src/burn_test.sh',
            'log_filename': 'stage5_gpu_burn.txt',
            'script_args': ["--stage-one", "1", "--stage-two", "1"],  # Shorter duration for parallel test
            'script_type': 'python'
        },
        {
            'name': 'NVME Test',
            'script_path': 'src/nvme_test.sh',
            'log_filename': 'stage5_nvme_test.txt',
            'script_type': 'bash'
        },
        {
            'name': 'Hotspot Test',
            'script_path': 'src/hotspot_test.sh',
            'log_filename': 'stage5_hotspot_test.txt',
            'script_type': 'bash'
        }
    ]
    
    print("⚠️  Note: This test will run for approximately 2+ hours due to GPU burn test duration")
    results = run_parallel_tests(parallel_configs)
    
    # Check if all parallel tests passed
    failed_tests = [name for name, success in results.items() if not success]
    if failed_tests:
        print(f"❌ Stage 5 failed - Failed tests: {', '.join(failed_tests)}")
        sys.exit(1)
    else:
        print("✅ Stage 5 completed - All parallel tests passed!")
    
    print("\n=== QA Test Suite Completed ===")

if __name__ == "__main__":
    main()

