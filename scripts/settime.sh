#!/bin/sh

BASE=0x80600100
SETTIME=0x20
POKE=/root/bin/poke
PEEK=/root/bin/peek

date

# Current time in seconds
a=`date +%s`

# Add one second, convert back to HMS
b=`date --date=@$(($a + 1)) +%H%M%S`

# Set time at next second
$POKE $(($BASE+$SETTIME)) 0x$b
