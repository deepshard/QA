#!/usr/bin/env python3

import os
import subprocess
import sys
import threading
import time
import requests
import socket
from pathlib import Path
from datetime import datetime

#qa starts heres

#log fille
LOG_DIR = "/home/truffle/qa_logs"
BACKEND_URL = "https://649025862b65.ngrok.app/qa/upload"
BACKEND_API_URL = "https://649025862b65.ngrok.app/qa"
STREAM_INTERVAL = 10  # seconds

# Stage mapping to backend enums
STAGE_MAPPING = {
    0: "setup",
    1: "led", 
    2: "nvme",
    3: "hotspot",
    4: "gpu",
    5: "final",
    6: "done"
}

def get_hostname():
    """Get the truffle hostname"""
    try:
        return socket.gethostname()
    except:
        return "truffle-unknown"

def get_current_stage():
    """Get current stage from backend for this device"""
    hostname = get_hostname()
    try:
        response = requests.get(f"{BACKEND_API_URL}/{hostname}", timeout=10)
        if response.status_code == 200:
            data = response.json()
            current_stage = data.get('stage', 'setup')
            print(f"📡 Backend reports current stage: {current_stage}")
            
            # Convert backend stage to our stage number
            for stage_num, stage_name in STAGE_MAPPING.items():
                if stage_name == current_stage:
                    return stage_num
            return 0  # Default to setup if unknown stage
        else:
            print(f"⚠️ Failed to get stage from backend: {response.status_code}")
            return 0
    except Exception as e:
        print(f"❌ Error getting stage from backend: {e}")
        return 0

def update_stage(stage_number):
    """Update stage in backend for this device"""
    hostname = get_hostname()
    stage_name = STAGE_MAPPING.get(stage_number, "setup")
    
    try:
        # Send stage update in the file upload request
        data = {
            'name': hostname,
            'stage': stage_name
        }
        
        files = {"_": ("", "")}
        response = requests.post(BACKEND_URL, data=data, files=files, timeout=10)
        if response.status_code == 200:
            print(f"📡 Updated backend stage to: {stage_name}")
            return True
        else:
            print(f"⚠️ Failed to update stage: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Error updating stage: {e}")
        return False

def upload_log_file(log_filename, param_name, current_stage=None):
    """Upload the current log file to backend (simple one-time upload)"""
    hostname = get_hostname()
    log_path = os.path.join(LOG_DIR, log_filename)
    csv_path = os.path.join(LOG_DIR, "burn_test.csv")  # GPU burn test CSV
    
    try:
        files = {}
        data = {'name': hostname}
        
        # Include stage information if provided
        if current_stage is not None:
            stage_name = STAGE_MAPPING.get(current_stage, "setup")
            data['stage'] = stage_name
        
        # Always upload the main log file if it exists
        if os.path.exists(log_path):
            with open(log_path, 'rb') as f:
                files[param_name] = (log_filename, f.read(), 'text/plain')
        
        # For GPU tests, also upload the CSV file if it exists
        if "gpu" in param_name.lower() and os.path.exists(csv_path):
            with open(csv_path, 'rb') as f:
                files['gpuTestGraph'] = ('burn_test.csv', f.read(), 'text/csv')
        
        if files:
            response = requests.post(BACKEND_URL, files=files, data=data, timeout=30)
            if response.status_code == 200:
                file_list = list(files.keys())
                print(f"📤 Uploaded {', '.join(file_list)} to backend")
                return True
            else:
                print(f"⚠️ Failed to upload files: {response.status_code}")
                return False
        else:
            print(f"⚠️ No log file found to upload: {log_path}")
            return False
            
    except Exception as e:
        print(f"❌ Error uploading {log_filename}: {e}")
        return False

def periodic_upload_worker(log_filename, param_name, stop_event, current_stage=None):
    """Worker that uploads log file every STREAM_INTERVAL seconds"""
    while not stop_event.is_set():
        upload_log_file(log_filename, param_name, current_stage)
        # Wait for the interval or until stop is requested
        stop_event.wait(STREAM_INTERVAL)

def start_periodic_upload(log_filename, param_name, current_stage=None):
    """Start periodic uploading of a log file in a background thread"""
    stop_event = threading.Event()
    upload_thread = threading.Thread(
        target=periodic_upload_worker, 
        args=(log_filename, param_name, stop_event, current_stage)
    )
    upload_thread.daemon = True
    upload_thread.start()
    return stop_event

def setup_logging():
    """Create log directory structure"""
    os.makedirs(LOG_DIR, exist_ok=True)
    print(f"Log directory set up at: {LOG_DIR}")

def run_script_with_logging(script_path, log_filename, script_args=None, script_type="bash", stream_param=None, current_stage=None):
    """Run a script and capture its output to a log file with optional streaming"""
    log_path = os.path.join(LOG_DIR, log_filename)
    script_abs_path = os.path.abspath(script_path)
    
    if not os.path.exists(script_abs_path):
        print(f"Error: Script {script_abs_path} not found")
        return False
    
    print(f"Running {script_abs_path} -> {log_path}")
    
    # Start periodic uploading if requested
    upload_stop_event = None
    if stream_param:
        print(f"📡 Starting periodic upload for {log_filename}")
        upload_stop_event = start_periodic_upload(log_filename, stream_param, current_stage)
    
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
        
        # Stop uploading
        if upload_stop_event:
            upload_stop_event.set()
            print(f"📡 Stopped periodic upload for {log_filename}")
            
        # Final upload to ensure we capture the complete log
        if stream_param:
            print(f"📡 Final upload for {log_filename}")
            upload_log_file(log_filename, stream_param, current_stage)
            
        if result.returncode == 0:
            print(f"✅ {script_path} completed successfully")
            return True
        else:
            print(f"❌ {script_path} failed with exit code {result.returncode}")
            return False
            
    except Exception as e:
        # Stop uploading on error
        if upload_stop_event:
            upload_stop_event.set()
        # Final upload to capture any partial logs
        if stream_param:
            print(f"📡 Final upload for {log_filename} (after error)")
            upload_log_file(log_filename, stream_param, current_stage)
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
        stream_param = config.get('stream_param', None)
        current_stage = config.get('current_stage', None)
        
        print(f"Starting {name} in parallel...")
        success = run_script_with_logging(script_path, log_filename, script_args, script_type, stream_param, current_stage)
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
    
    # Get current stage from backend to resume from where we left off
    start_stage = get_current_stage()
    print(f"🔄 Resuming from stage {start_stage} ({STAGE_MAPPING.get(start_stage, 'unknown')})")
    
    # Check if we're already done
    if start_stage >= 6:
        print("✅ All QA tests already completed - system is in 'done' state")
        print("🎉 === QA Test Suite Already Complete === 🎉")
        return
    
    # Stage 0: System setup and configuration
    if start_stage <= 0:
        print("\n--- Stage 0: System Setup ---")
        update_stage(0)  # Update backend that we're starting setup
        success = run_script_with_logging("src/stage0.sh", "stage0_logs.txt", current_stage=0)
        
        if not success:
            print("❌ Stage 0 failed, stopping test suite")
            sys.exit(1)
        
        update_stage(1)  # Move to next stage
        print("✅ Stage 0 completed - Updated backend to LED stage")
    else:
        print("⏭️ Skipping Stage 0 (already completed)")
    
    # Stage 1: LED Test
    if start_stage <= 1:
        print("\n--- Stage 1: LED Test ---")
        update_stage(1)  # Update backend that we're starting LED test
        success = run_script_with_logging("src/led_test.sh", "led_test.txt", stream_param="ledTestFile", current_stage=1)
        
        if not success:
            print("❌ LED test failed, stopping test suite")
            sys.exit(1)
        
        update_stage(2)  # Move to next stage
        print("✅ Stage 1 completed - Updated backend to NVME stage")
    else:
        print("⏭️ Skipping Stage 1 (already completed)")
    
    # Stage 2: NVME Test
    if start_stage <= 2:
        print("\n--- Stage 2: NVME Test ---")
        update_stage(2)  # Update backend that we're starting NVME test
        success = run_script_with_logging("src/nvme_test.sh", "nvme_test.txt", stream_param="nvmeTestFile", current_stage=2)
        
        if not success:
            print("❌ NVME test failed, stopping test suite")
            sys.exit(1)
        
        update_stage(3)  # Move to next stage
        print("✅ Stage 2 completed - Updated backend to Hotspot stage")
    else:
        print("⏭️ Skipping Stage 2 (already completed)")
    
    # Stage 3: Hotspot Test
    if start_stage <= 3:
        print("\n--- Stage 3: Hotspot Test ---")
        update_stage(3)  # Update backend that we're starting Hotspot test
        success = run_script_with_logging("src/hotspot_test.sh", "hotspot_test.txt", stream_param="hotspotTestFile", current_stage=3)
        
        if not success:
            print("❌ Hotspot test failed, stopping test suite")
            sys.exit(1)
        
        update_stage(4)  # Move to next stage
        print("✅ Stage 3 completed - Updated backend to GPU stage")
    else:
        print("⏭️ Skipping Stage 3 (already completed)")
    
    # Stage 4: GPU Burn Test
    if start_stage <= 4:
        print("\n--- Stage 4: GPU Burn Test ---")
        update_stage(4)  # Update backend that we're starting GPU test
        burn_args = ["--stage-one", "0.01", "--stage-two", "0.01"]
        success = run_script_with_logging("src/burn_test.py", "burn_test.txt", burn_args, "python", "gpuTestFile", current_stage=4)
        
        if not success:
            print("❌ GPU burn test failed, stopping test suite")
            sys.exit(1)
        
        update_stage(5)  # Move to final stage
        print("✅ Stage 4 completed - Updated backend to Final stage")
    else:
        print("⏭️ Skipping Stage 4 (already completed)")
    
    # Stage 5: Parallel Stress Test (Final)
    if start_stage <= 5:
        print("\n--- Stage 5: Final Parallel Stress Test ---")
        update_stage(5)  # Update backend that we're starting final test
        print("Running GPU burn test, NVME test, and hotspot test simultaneously...")
        
        parallel_configs = [
            {
                'name': 'GPU Burn Test',
                'script_path': 'src/burn_test.py',
                'log_filename': 'stage5_gpu_burn.txt',
                'script_args': ["--stage-one", "0.01", "--stage-two", "0.01"],  # Shorter duration for parallel test
                'script_type': 'python',
                'stream_param': 'stage5GpuTestFile',
                'current_stage': 5
            },
            {
                'name': 'NVME Test',
                'script_path': 'src/nvme_test.sh',
                'log_filename': 'stage5_nvme_test.txt',
                'script_type': 'bash',
                'stream_param': 'stage5NvmeTestFile',
                'current_stage': 5
            },
            {
                'name': 'Hotspot Test',
                'script_path': 'src/hotspot_test.sh',
                'log_filename': 'stage5_hotspot_test.txt',
                'script_type': 'bash',
                'stream_param': 'stage5HotspotTestFile',
                'current_stage': 5
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
            # Mark as fully complete in backend
            update_stage(6)  # Set to "done" stage
            print("📡 Updated backend to 'done' state - QA testing complete!")
    else:
        print("⏭️ All stages already completed!")
    
    print("\n🎉 === QA Test Suite Completed Successfully === 🎉")

if __name__ == "__main__":
    main()

