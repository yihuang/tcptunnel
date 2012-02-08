#!/bin/sh
./Echo 1081 &
sleep 1
dist/build/tcptunnel/tcptunnel remote 127.0.0.1 8000 &
sleep 1
dist/build/tcptunnel/tcptunnel local 127.0.0.1 8000 &
echo "try telnet 127.0.0.1 1082"
