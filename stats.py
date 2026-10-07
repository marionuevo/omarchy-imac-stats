#!/usr/bin/env python3
import glob
import json
import os
import re
import shutil
import subprocess
import time

FAN_STATUS = "/run/imac-fan/status.json"


def hwmon_chip(name):
    for f in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            if open(f).read().strip() == name:
                return os.path.dirname(f)
        except OSError:
            pass
    return None


def temp_by_label(chip_name, label):
    base = hwmon_chip(chip_name)
    if not base:
        return None
    for f in glob.glob(base + "/temp*_label"):
        try:
            if open(f).read().strip() != label:
                continue
        except OSError:
            continue
        idx = os.path.basename(f)[len("temp"):-len("_label")]
        try:
            return round(int(open(base + "/temp" + idx + "_input").read().strip()) / 1000)
        except OSError:
            return None
    return None


def fan_rpm():
    # applesmc registers no hwmon name file on this kernel, so go through the
    # platform device instead of hwmon_chip().
    for path in glob.glob("/sys/devices/platform/applesmc.*/fan1_input"):
        try:
            return int(open(path).read().strip())
        except (OSError, ValueError):
            pass
    return None


def fan_status():
    """What imac-fand is doing, or None if it isn't running.

    A status file older than a few seconds means the daemon died or was
    stopped, and its numbers describe a fan nobody is steering any more.
    """
    try:
        with open(FAN_STATUS) as f:
            status = json.load(f)
    except (OSError, ValueError):
        return None
    if time.time() - status.get("time", 0) > 5:
        return None
    return status


def start_gpu_usage():
    # gpu_busy_percent is not implemented for this Southern Islands Radeon;
    # radeontop samples the GPU's busy bits for one second instead. Started
    # first so its second overlaps the CPU sample below.
    try:
        return subprocess.Popen(
            ["radeontop", "-d", "-", "-l", "1"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
    except OSError:
        return None


def finish_gpu_usage(proc):
    if not proc:
        return None
    try:
        out, _ = proc.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        return None
    m = re.search(r"gpu ([\d.]+)%", out)
    return round(float(m.group(1))) if m else None


def cpu_usage():
    def read():
        with open("/proc/stat") as f:
            vals = [int(x) for x in f.readline().split()[1:]]
        return sum(vals), vals[3] + vals[4]

    t1, i1 = read()
    time.sleep(0.3)
    t2, i2 = read()
    dt = t2 - t1 or 1
    return round(100 * (dt - (i2 - i1)) / dt)


def mem_usage():
    d = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, value = line.split(":", 1)
            d[key] = int(value.split()[0])
    total, avail = d.get("MemTotal", 0), d.get("MemAvailable", 0)
    return round(100 * (total - avail) / total) if total else 0


def disk_usage():
    usage = shutil.disk_usage("/")
    return round(100 * usage.used / usage.total) if usage.total else 0


gpu_proc = start_gpu_usage()
cpu_temp = temp_by_label("coretemp", "Package id 0")
gpu_temp = temp_by_label("amdgpu", "edge")
cpu_pct = cpu_usage()
ram_pct = mem_usage()
disk_pct = disk_usage()
gpu_pct = finish_gpu_usage(gpu_proc)
fan = fan_rpm()
daemon = fan_status()

print(json.dumps({
    "fan": fan,
    "fanTarget": daemon.get("target") if daemon else None,
    "fanMin": daemon.get("min") if daemon else None,
    "fanMax": daemon.get("max") if daemon else None,
    "source": daemon.get("source") if daemon else None,
    "daemon": daemon is not None,
    "cpuTemp": cpu_temp,
    "gpuTemp": gpu_temp,
    "cpu": cpu_pct,
    "gpu": gpu_pct,
    "ram": ram_pct,
    "disk": disk_pct,
}))
