#!/usr/bin/env python3

import serial
import subprocess
import getpass
import time
import toml

def debug_print(ln):
    if debug:
        print(ln)

def error_print(ln):
    print("ERROR: " + ln)

def send_command(cmd):
    ser.write((cmd.encode("utf-8") + b'\r\n'))
    ser.flush()
    time.sleep(0.01)

debug = True # Use for additional info for debugging
config = toml.load("/tmp/coremark/serial-test-config.toml")

for i in ["U-Boot", "Bitfile"]:
    result = 1
    while result != 0:
        result = subprocess.call((config[i]["flash_cmd"] + " " +
                                  config[i]["path"]).split(" "))
        
    debug_print(i + " flash succesful.")

port_name = config["Connection"]["port_name"]
baud_rate = config["Connection"]["baud_rate"]
ser = None

try:
    ser = serial.Serial(port_name, baud_rate, timeout=1)
    time.sleep(5) # Wait for device to initialize
    debug_print("Connected to " + port_name)

    ser.flush()
    result = subprocess.call(["cpu_reset"])

    while True:
        line = ser.readline().decode("utf-8").strip()
        debug_print("Received: " + line)
        if "login:" in line:
            send_command(input("Enter login:"))
        elif "Password" in line:
            send_command(getpass.getpass())
            time.sleep(5) # Wait for Password check
            if ser.in_waiting:
                break

    debug_print("Login successful.")

except serial.SerialException as e:
    error_print("Error opening serial port " + str(e))
except KeyboardInterrupt:
    error_print("Program terminated by user")
finally:
    if ser and ser.is_open:
        ser.close()
        debug_print("Serial port closed")
