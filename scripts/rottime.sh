#!/bin/bash

DISPBASE=0x80600300
PDM=0x0
DP=0x4
PRINTBASE=0x80601000
DACBASE=0x80600100

POKE=/root/bin/poke
PEEK=/root/bin/peek

$POKE $(($DISPBASE+$PDM))  0x280

for i in {0..63..4}; do
    $POKE $(($PRINTBASE+$i)) 0x00200020
done

# 20202020 20202020 20202020 20202020 20888720 86852084 83828180 20202020
disp0=008800870020008600850020008401830082008100800020
disp1=0020002000200020
disp2=00200020008800870020008600850020008401830082008100800020
disp3=0020002000200020
disp4=00200020
dp2=000000010000000000
pos=0

while true; do
    #dp16=`echo "ibase=2; $dp2" | bc`
    adc=`${PEEK} 0x80600124`

    str=
    for i in {6..9}; do
	val=$((0x${adc:$i:1}))
	if [ $val -eq 11 ]; then
	    tmp="0062"
	else
	    if [ $val -lt 10 ]; then
		tmp=`printf "00%02x" $(($val+0x30))`
	    else 
		tmp=`printf "00%02x" $(($val+0x37))`
	    fi;
	fi;
	str=$str$tmp
    done

    #disp=$disp0$disp1$disp2$disp3$disp4
    disp=$disp0$str$disp2$str$disp4

    #$POKE $(($DISPBASE+$DP))   $dp16
    $POKE $(($PRINTBASE+0x0))  	0x${disp:$(($pos * 4 + 60)):8}
    $POKE $(($PRINTBASE+0x4))  	0x${disp:$(($pos * 4 + 52)):8}
    $POKE $(($PRINTBASE+0x8))  	0x${disp:$(($pos * 4 + 44)):8}
    $POKE $(($PRINTBASE+0xc))  	0x${disp:$(($pos * 4 + 36)):8}
    $POKE $(($PRINTBASE+0x10))  0x${disp:$(($pos * 4 + 28)):8}
    $POKE $(($PRINTBASE+0x14))  0x${disp:$(($pos * 4 + 20)):8}
    $POKE $(($PRINTBASE+0x18))  0x${disp:$(($pos * 4 + 12)):8}
    $POKE $(($PRINTBASE+0x1c))  0x${disp:$(($pos * 4 + 4)):8}
    $POKE $(($PRINTBASE+0x20)) 0x0020${disp:$(($pos * 4 + 0)):4}

    sleep 0.3

    pos=$((($pos + 1) % 18))
    #disp=${disp:2:34}${disp:0:2}
    #dp2=${dp2:1:17}${dp2:0:1}

done

