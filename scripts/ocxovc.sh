#!/bin/bash
#
# Scan the DAC and measure the frequency of the OCXO relative to the GPS PPS
#

BASE=0x80600100
FREQ=0x14
DAC=0x24

POKE=/root/bin/poke
PEEK=/root/bin/peek


for i in {0..65280..256} 65535; do
    $POKE $(($BASE+$DAC))  $i
    sleep 8;

    valhex=`$PEEK $(($BASE+$FREQ))`
    val=$(($valhex + 0))

    (( val > 0x7fffffff )) && (( val -= 0x100000000 ))
    echo $i $val `printf "0x%04x" $i` $valhex ;
done

