
######################################################################
#  Xilinx u-boot build

# u-boot version 2020.1 has these ps7_init files, not sure if a custom
# one is needed
#u-boot/board/xilinx/zynq/zynq-microzed/ps7_init_gpl.c: fpga/cpu/ip/cpu_processing_system7_0_0/ps7_init_gpl.c
#	cp $? $@

#u-boot/board/xilinx/zynq/zynq-microzed/ps7_init_gpl.h: fpga/cpu/ip/cpu_processing_system7_0_0/ps7_init_gpl.h
#	cp $? $@

# Use host cross compiler to build instead of the one in the SDK
u-boot/u-boot.elf:
	export DEVICE_TREE=zynq-microzed && ${MAKE} -C u-boot xilinx_zynq_virt_defconfig
	export DEVICE_TREE=zynq-microzed && ${MAKE} -C u-boot CROSS_COMPILE=arm-linux-gnueabihf-

boot/boot.scr: boot/boot.script
	mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Clock boot script" -d $? $@

u-boot: u-boot/u-boot.elf boot/boot.scr


######################################################################
#  Xilinx fpga and First Stage Boot Loader
fpga/vhd/clock/clock.runs/impl_1/clock.bin:
	${MAKE} -C fpga/vhd
	${MAKE} -C fpga/vhd fsbl

boot/system.bit.bin: fpga/vhd/clock/clock.runs/impl_1/clock.bin
	cp $? $@

fpga: boot/system.bit.bin


######################################################################
#  Xilinx boot ROM
#u-boot/u-boot.elf: u-boot/u-boot
#	cp $? $@
#	arm-xilinx-linux-gnueabi-strip $@

boot/BOOT.bin: scripts/fsbl.bif fpga/vhd/fsbl/clock/Release/clock.elf u-boot/u-boot.elf
	bootgen -image scripts/fsbl.bif -w -o boot/BOOT.bin

boot: fpga boot/BOOT.bin


######################################################################
#  Xilinx linux kernel build

# Pickup tools from u-boot in PATH
PATH := ${PATH}:${PWD}/u-boot/tools

linux/.config:
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- xilinx_zynq_defconfig

linux/arch/arm/boot/uImage: linux/.config
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- UIMAGE_LOADADDR=0x8000 uImage

linux: linux/arch/arm/boot/uImage


######################################################################
debug:
	@echo PATH=${PATH}
	@echo PWD=${PWD}
