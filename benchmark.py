import subprocess
import time
import re
import ctypes
import ctypes.wintypes

EnumWindows = ctypes.windll.user32.EnumWindows
EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int))
GetWindowThreadProcessId = ctypes.windll.user32.GetWindowThreadProcessId
GetWindowText = ctypes.windll.user32.GetWindowTextW
GetWindowTextLength = ctypes.windll.user32.GetWindowTextLengthW

def get_window_title_for_pid(target_pid):
    title = ""
    def foreach_window(hwnd, lParam):
        nonlocal title
        pid = ctypes.wintypes.DWORD()
        GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value == target_pid:
            length = GetWindowTextLength(hwnd)
            if length > 0:
                buff = ctypes.create_unicode_buffer(length + 1)
                GetWindowText(hwnd, buff, length + 1)
                window_text = buff.value
                print(f"Window title: '{window_text}'")
                if "FPS" in window_text or "fps" in window_text.lower():
                    title = window_text
                    return False # Stop enumerating
        return True
    
    EnumWindows(EnumWindowsProc(foreach_window), 0)
    return title

def benchmark_eden(exe_path, rom_path, duration=30):
    print(f"Starting {exe_path}...")
    proc = subprocess.Popen([exe_path, rom_path])
    
    print("Waiting 15 seconds for boot...")
    time.sleep(15)
    
    print(f"Benchmarking for {duration} seconds...")
    start = time.time()
    fps_records = []
    
    while time.time() - start < duration:
        if proc.poll() is not None:
            print("Emulator exited prematurely.")
            break
            
        title = get_window_title_for_pid(proc.pid)
        if title:
            match = re.search(r"FPS[:\s]+(\d+)|(\d+)[\s]+FPS", title, re.IGNORECASE)
            if match:
                fps = int(match.group(1) or match.group(2))
                fps_records.append(fps)
                print(f"Captured: {fps} FPS")
        time.sleep(2.0) # SDL updates title every 2 seconds
        
    print("Terminating emulator...")
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        
    if fps_records:
        avg = sum(fps_records) / len(fps_records)
        print(f"\n--- Benchmark Results ---")
        print(f"Executable: {exe_path}")
        print(f"Average FPS: {avg:.2f}")
        print(f"Min FPS: {min(fps_records)}")
        print(f"Max FPS: {max(fps_records)}")
        print(f"-------------------------")
    else:
        print("\nCould not capture any FPS data.")

import sys
if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python benchmark.py <exe_path> <rom_path>")
        sys.exit(1)
    benchmark_eden(sys.argv[1], sys.argv[2])
