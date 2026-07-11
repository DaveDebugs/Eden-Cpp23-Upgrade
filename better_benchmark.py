import sys
import subprocess
import time
import csv
import os

def benchmark(exe_path, rom_path, duration=30):
    print(f"Starting emulator: {exe_path}")
    emu_proc = subprocess.Popen([exe_path, rom_path])

    print("Waiting 15 seconds for emulator to boot and game to load...")
    time.sleep(15)

    if emu_proc.poll() is not None:
        print("Emulator exited prematurely.")
        return

    csv_file = "frametimes.csv"
    if os.path.exists(csv_file):
        os.remove(csv_file)

    print(f"Starting PresentMon for {duration} seconds...")
    presentmon_exe = r"P:\Programming Repositories\eden\PresentMon.exe"
    
    process_name = os.path.basename(exe_path)
    
    pm_cmd = [
        presentmon_exe,
        "--process_name", process_name,
        "--output_file", csv_file,
        "--timed", str(duration),
        "--terminate_after_timed"
    ]
    
    pm_proc = subprocess.Popen(pm_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pm_proc.wait()

    print("Terminating emulator...")
    emu_proc.terminate()
    try:
        emu_proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        emu_proc.kill()

    if not os.path.exists(csv_file):
        print("Error: PresentMon did not generate a CSV file.")
        return

    frame_times = []
    with open(csv_file, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        # Depending on PresentMon version, the column could be 'msBetweenPresents' or 'msBetweenDisplayChange'
        # In PresentMon 2.x it's typically msBetweenPresents
        ms_col = None
        for row in reader:
            if ms_col is None:
                if 'MsBetweenPresents' in row:
                    ms_col = 'MsBetweenPresents'
                elif 'MsBetweenDisplayChange' in row:
                    ms_col = 'MsBetweenDisplayChange'
                else:
                    print(f"Error: Unknown CSV format. Columns: {list(row.keys())}")
                    return

            try:
                ft = float(row[ms_col])
                frame_times.append(ft)
            except ValueError:
                pass

    if not frame_times:
        print("Error: No frame times recorded in the CSV file. Was the game rendering?")
        return

    fps_list = [1000.0 / ft for ft in frame_times if ft > 0]
    
    if not fps_list:
        print("No valid FPS data.")
        return

    avg_fps = sum(fps_list) / len(fps_list)
    min_fps = min(fps_list)
    max_fps = max(fps_list)
    
    sorted_ft = sorted(frame_times, reverse=True)
    one_percent_idx = max(0, len(sorted_ft) // 100)
    one_percent_low_fps = 1000.0 / sorted_ft[one_percent_idx]

    print(f"\n=== Benchmark Results for {process_name} ===")
    print(f"Total Frames: {len(fps_list)}")
    print(f"Average FPS:  {avg_fps:.2f}")
    print(f"1% Low FPS:   {one_percent_low_fps:.2f}")
    print(f"Max FPS:      {max_fps:.2f}")
    print(f"Min FPS:      {min_fps:.2f}")
    print("=========================================\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python better_benchmark.py <exe_path> <rom_path>")
        sys.exit(1)
    
    benchmark(sys.argv[1], sys.argv[2])
