#!/usr/bin/bash

picocom /dev/ttyUSB0 -b 115200 --logfile uart_dumps/dump.log
# tio /dev/ttyUSB0 -b 115200 -l --log-file uart_dumps/dump.log --timestamp
