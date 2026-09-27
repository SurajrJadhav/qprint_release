#!/usr/bin/env python3
"""
Project Manager - File Sharing Application
Manages backend (Go) and frontend (Next.js) processes
"""

import subprocess
import sys
import os
import signal
import time
import json
import webbrowser
from pathlib import Path

# Configuration
BACKEND_DIR = "backend"
FRONTEND_DIR = "frontend"
PID_FILE = "project.pid"

class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text.center(60)}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}\n")

def print_success(text):
    print(f"{Colors.OKGREEN}✓ {text}{Colors.ENDC}")

def print_error(text):
    print(f"{Colors.FAIL}✗ {text}{Colors.ENDC}")

def print_info(text):
    print(f"{Colors.OKCYAN}ℹ {text}{Colors.ENDC}")

def print_warning(text):
    print(f"{Colors.WARNING}⚠ {text}{Colors.ENDC}")

def save_pids(backend_pid, frontend_pid):
    """Save process IDs to file"""
    with open(PID_FILE, 'w') as f:
        json.dump({
            'backend': backend_pid,
            'frontend': frontend_pid
        }, f)
    print_success(f"PIDs saved to {PID_FILE}")

def load_pids():
    """Load process IDs from file"""
    if not os.path.exists(PID_FILE):
        return None, None
    
    try:
        with open(PID_FILE, 'r') as f:
            pids = json.load(f)
            return pids.get('backend'), pids.get('frontend')
    except:
        return None, None

def is_process_running(pid):
    """Check if a process is running"""
    if pid is None:
        return False
    
    try:
        # On Windows, use tasklist
        if sys.platform == 'win32':
            result = subprocess.run(['tasklist', '/FI', f'PID eq {pid}'], 
                                  capture_output=True, text=True)
            return str(pid) in result.stdout
        else:
            # On Unix-like systems, send signal 0
            os.kill(pid, 0)
            return True
    except (OSError, subprocess.SubprocessError):
        return False

def kill_process(pid):
    """Kill a process by PID"""
    if pid is None:
        return False
    
    try:
        if sys.platform == 'win32':
            subprocess.run(['taskkill', '/F', '/PID', str(pid)], 
                         capture_output=True)
        else:
            os.kill(pid, signal.SIGTERM)
            time.sleep(1)
            if is_process_running(pid):
                os.kill(pid, signal.SIGKILL)
        return True
    except:
        return False

def start_backend():
    """Start the Go backend server"""
    print_info("Starting backend server...")
    
    backend_path = Path(BACKEND_DIR)
    if not backend_path.exists():
        print_error(f"Backend directory '{BACKEND_DIR}' not found!")
        return None
    
    try:
        # Check if on Windows
        if sys.platform == 'win32':
            # Start Go server in new window (stays open)
            process = subprocess.Popen(
                ['start', 'cmd', '/k', 'go', 'run', 'cmd/api/main.go'],
                cwd=BACKEND_DIR,
                shell=True
            )
            time.sleep(3)  # Give it time to start
            # Check if port is in use (backend started)
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            result = sock.connect_ex(('localhost', 8080))
            sock.close()
            if result == 0:
                print_success("Backend started in new window")
                print_info("Backend running on http://localhost:8080")
                return 1  # Return dummy PID (we'll use port-based detection)
            else:
                print_error("Backend failed to start. Check the Backend window for errors.")
                return None
        else:
            # Unix-like: start in background
            process = subprocess.Popen(
                ['go', 'run', 'cmd/api/main.go'],
                cwd=BACKEND_DIR,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=os.setsid
            )
            time.sleep(3)
            if process.poll() is None:
                print_success(f"Backend started (PID: {process.pid})")
                print_info("Backend running on http://localhost:8080")
                return process.pid
            else:
                print_error("Backend failed to start")
                return None
    except FileNotFoundError:
        print_error("Go is not installed or not in PATH")
        return None
    except Exception as e:
        print_error(f"Failed to start backend: {e}")
        return None

def start_frontend():
    """Start the Next.js frontend server"""
    print_info("Starting frontend server...")
    
    frontend_path = Path(FRONTEND_DIR)
    if not frontend_path.exists():
        print_error(f"Frontend directory '{FRONTEND_DIR}' not found!")
        return None
    
    # Check if node_modules exists
    if not (frontend_path / 'node_modules').exists():
        print_warning("node_modules not found. Installing dependencies...")
        print_info("This may take a few minutes...")
        try:
            # Run npm install in the same shell, showing output
            result = subprocess.run(
                ['npm', 'install'], 
                cwd=FRONTEND_DIR, 
                check=True,
                capture_output=False,  # Show output in console
                text=True
            )
            print_success("Dependencies installed")
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to install dependencies. Error code: {e.returncode}")
            print_error("Please run 'npm install' manually in the frontend directory")
            return None
        except FileNotFoundError:
            print_error("npm is not installed or not in PATH")
            print_info("Install Node.js from: https://nodejs.org/")
            return None
    
    try:
        # Start Next.js dev server
        if sys.platform == 'win32':
            # Start in new window (stays open)
            process = subprocess.Popen(
                ['start', 'cmd', '/k', 'npm', 'run', 'dev'],
                cwd=FRONTEND_DIR,
                shell=True
            )
            time.sleep(5)  # Give it time to start
            # Check if port is in use
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            result = sock.connect_ex(('localhost', 3000))
            sock.close()
            if result == 0:
                print_success("Frontend started in new window")
                print_info("Frontend running on http://localhost:3000")
                return 1  # Return dummy PID
            else:
                print_error("Frontend failed to start. Check the Frontend window for errors.")
                return None
        else:
            # Unix-like: start in background
            process = subprocess.Popen(
                ['npm', 'run', 'dev'],
                cwd=FRONTEND_DIR,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=os.setsid
            )
            time.sleep(5)
            if process.poll() is None:
                print_success(f"Frontend started (PID: {process.pid})")
                print_info("Frontend running on http://localhost:3000")
                return process.pid
            else:
                print_error("Frontend failed to start")
                return None
    except FileNotFoundError:
        print_error("npm is not installed or not in PATH")
        return None
    except Exception as e:
        print_error(f"Failed to start frontend: {e}")
        return None

def start_project():
    """Start both backend and frontend"""
    print_header("Starting File Sharing Application")
    
    # Check if already running
    backend_pid, frontend_pid = load_pids()
    if is_process_running(backend_pid) or is_process_running(frontend_pid):
        print_warning("Project is already running!")
        print_info("Use 'python manage.py stop' to stop it first")
        return
    
    # Start backend
    backend_pid = start_backend()
    
    # Start frontend
    frontend_pid = start_frontend()
    
    # Save PIDs
    if backend_pid or frontend_pid:
        save_pids(backend_pid, frontend_pid)
        print_header("Application Started Successfully")
        print_success("Backend: http://localhost:8080")
        print_success("Frontend: http://localhost:3000")
        print_info(f"\nTo stop: python {sys.argv[0]} stop")
        
        # Open browser if frontend started successfully
        if frontend_pid:
            print_info("Opening browser...")
            time.sleep(2)  # Wait a bit more for frontend to be ready
            try:
                webbrowser.open('http://localhost:3000')
                print_success("Browser opened!")
            except Exception as e:
                print_warning(f"Could not open browser automatically: {e}")
                print_info("Please open http://localhost:3000 manually")
    else:
        print_error("Failed to start application")

def stop_project():
    """Stop both backend and frontend"""
    print_header("Stopping File Sharing Application")
    
    backend_pid, frontend_pid = load_pids()
    
    stopped = False
    
    # Stop backend
    if backend_pid and is_process_running(backend_pid):
        print_info(f"Stopping backend (PID: {backend_pid})...")
        if kill_process(backend_pid):
            print_success("Backend stopped")
            stopped = True
        else:
            print_error("Failed to stop backend")
    else:
        print_info("Backend is not running")
    
    # Stop frontend
    if frontend_pid and is_process_running(frontend_pid):
        print_info(f"Stopping frontend (PID: {frontend_pid})...")
        if kill_process(frontend_pid):
            print_success("Frontend stopped")
            stopped = True
        else:
            print_error("Failed to stop frontend")
    else:
        print_info("Frontend is not running")
    
    # Remove PID file
    if os.path.exists(PID_FILE):
        os.remove(PID_FILE)
        print_success("Cleaned up PID file")
    
    if stopped:
        print_header("Application Stopped")
    else:
        print_warning("No running processes found")

def restart_project():
    """Restart both backend and frontend"""
    print_header("Restarting File Sharing Application")
    stop_project()
    time.sleep(2)
    start_project()

def status_project():
    """Check status of backend and frontend"""
    print_header("Application Status")
    
    backend_pid, frontend_pid = load_pids()
    
    # Check backend
    if backend_pid and is_process_running(backend_pid):
        print_success(f"Backend is running (PID: {backend_pid})")
        print_info("  URL: http://localhost:8080")
    else:
        print_error("Backend is not running")
    
    # Check frontend
    if frontend_pid and is_process_running(frontend_pid):
        print_success(f"Frontend is running (PID: {frontend_pid})")
        print_info("  URL: http://localhost:3000")
    else:
        print_error("Frontend is not running")
    
    print()

def show_help():
    """Show help message"""
    print_header("File Sharing Application Manager")
    print(f"{Colors.BOLD}Usage:{Colors.ENDC}")
    print(f"  python {sys.argv[0]} [command]")
    print(f"\n{Colors.BOLD}Commands:{Colors.ENDC}")
    print(f"  {Colors.OKGREEN}start{Colors.ENDC}     - Start backend and frontend servers")
    print(f"  {Colors.FAIL}stop{Colors.ENDC}      - Stop all running servers")
    print(f"  {Colors.WARNING}restart{Colors.ENDC}   - Restart all servers")
    print(f"  {Colors.OKCYAN}status{Colors.ENDC}    - Check status of servers")
    print(f"  {Colors.OKBLUE}help{Colors.ENDC}      - Show this help message")
    print()

def main():
    if len(sys.argv) < 2:
        show_help()
        return
    
    command = sys.argv[1].lower()
    
    commands = {
        'start': start_project,
        'stop': stop_project,
        'restart': restart_project,
        'status': status_project,
        'help': show_help
    }
    
    if command in commands:
        commands[command]()
    else:
        print_error(f"Unknown command: {command}")
        show_help()

if __name__ == "__main__":
    main()
