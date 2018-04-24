#!/bin/sh

DISPBASE=0x80600300
PDM=0x0
DP=0x4
PRINTBASE=0x806017c0

POKE=/root/bin/poke
PEEK=/root/bin/peek

$POKE $(($DISPBASE+$DP))  0xffffffff

$POKE $(($PRINTBASE+0x0))  0x01380138
$POKE $(($PRINTBASE+0x4))  0x01380138
$POKE $(($PRINTBASE+0x8))  0x01380138
$POKE $(($PRINTBASE+0xc))  0x01380138
$POKE $(($PRINTBASE+0x10)) 0x01380138
$POKE $(($PRINTBASE+0x14)) 0x01380138
$POKE $(($PRINTBASE+0x18)) 0x01380138
$POKE $(($PRINTBASE+0x1c)) 0x01380138
$POKE $(($PRINTBASE+0x20)) 0x01380138

$POKE $(($PRINTBASE+0x24)) 0x01380138
$POKE $(($PRINTBASE+0x28)) 0x01380138
$POKE $(($PRINTBASE+0x2c)) 0x01380138
$POKE $(($PRINTBASE+0x30)) 0x01380138
$POKE $(($PRINTBASE+0x34)) 0x01380138
$POKE $(($PRINTBASE+0x38)) 0x01380138
$POKE $(($PRINTBASE+0x3c)) 0x01380138

$POKE $(($DISPBASE+$PDM)) 0x180
