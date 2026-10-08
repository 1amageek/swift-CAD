import os, signal, subprocess, sys, time
seconds, log, *command = sys.argv[1:]
start = time.monotonic()
with open(log, "w") as output:
    process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        code = process.wait(timeout=int(seconds))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try: process.wait(timeout=2)
        except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait()
        code = 124
    print(f"BUILD exit={code} elapsed={time.monotonic()-start:.2f}s log={log}")
sys.exit(code)
