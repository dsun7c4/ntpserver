#!/bin/bash

DISPBASE=0x80600300
PDM=0x0
DP=0x4
PRINTBASE=0x80601000

POKE=/root/bin/poke
PEEK=/root/bin/peek

$POKE $(($DISPBASE+$PDM))  0x80
$POKE $(($PRINTBASE+0x14)) 0x20202020
$POKE $(($PRINTBASE+0x18)) 0x20202020
$POKE $(($PRINTBASE+0x1c)) 0x20202020

# 20202020 20202020 20202020 20202020 20888720 86852084 83828180 20202020
disp=202020888720868520848382818020202020
dp2=000000000010000000

while true; do
    dp16=`echo "ibase=2; $dp2" | bc`

    $POKE $(($DISPBASE+$DP))   $dp16
    $POKE $(($PRINTBASE+0x0))  0x${disp:28:8}
    $POKE $(($PRINTBASE+0x4))  0x${disp:20:8}
    $POKE $(($PRINTBASE+0x8))  0x${disp:12:8}
    $POKE $(($PRINTBASE+0xc))  0x${disp:4:8}
    $POKE $(($PRINTBASE+0x10)) 0x2020${disp:0:4}

    sleep 0.3

    disp=${disp:2:34}${disp:0:2}
    dp2=${dp2:1:17}${dp2:0:1}

done

