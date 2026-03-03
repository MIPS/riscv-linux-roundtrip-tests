#!/usr/bin/env python3

import serial
import subprocess
import getpass
import time
import toml

config = toml.load("/tmp/coremark/serial-test-config.toml")

for i in ["U-Boot", "Bitfile"]:
    result = 1
    while result != 0:
        result = subprocess.call((config[i]["flash_cmd"] + " " +
                                  config[i]["path"]).split(" "))
        
    print(i + " flash succesful.")

port_name = config["Connection"]["port_name"]
baud_rate = config["Connection"]["baud_rate"]
ser = None

try:
    ser = serial.Serial(port_name, baud_rate, timeout=1)
    time.sleep(5) # Wait for device to initialize
    print("Connected to " + port_name)

    ser.flush()
    result = subprocess.call(["cpu_reset"])

    while True:
        line = ser.readline().decode('utf-8').strip()
        print("Received: " + line)
        if "login:" in line:
            data = input("Enter login:").encode("utf-8")
            ser.write(data + b'\r\n')
            ser.flush()
        elif "Password" in line:
            data = getpass.getpass().encode("utf-8")
            ser.write(data + b'\r\n')
            ser.flush()
            time.sleep(10)
            if ser.in_waiting:
                break
        time.sleep(0.01)

except serial.SerialException as e:
    print("Error opening serial port " + str(e))
except KeyboardInterrupt:
    print("Program terminated by user")
finally:
    if ser and ser.is_open:
        ser.close()
        print("Serial port closed")
