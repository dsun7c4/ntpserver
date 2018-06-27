
######################################################################
#  Xilinx u-boot build

u-boot/board/xilinx/zynq/ps7_init_gpl.c: fpga/cpu/ip/cpu_processing_system7_0_0/ps7_init_gpl.c
	cp $? $@

u-boot/board/xilinx/zynq/ps7_init_gpl.h: fpga/cpu/ip/cpu_processing_system7_0_0/ps7_init_gpl.h
	cp $? $@

u-boot/u-boot: u-boot/board/xilinx/zynq/ps7_init_gpl.h u-boot/board/xilinx/zynq/ps7_init_gpl.c 
	${MAKE} -C u-boot zynq_microzed_defconfig
	${MAKE} -C u-boot CROSS_COMPILE=arm-xilinx-linux-gnueabi-

u-boot: u-boot/u-boot


######################################################################
#  Xilinx fpga and First Stage Boot Loader
fpga/clock/clock.runs/impl_1/clock.bin:
	${MAKE} -C fpga
	${MAKE} -C fpga fsbl

boot/system.bit.bin: fpga/clock/clock.runs/impl_1/clock.bin
	cp $? $@

fpga: boot/system.bit.bin


######################################################################
#  Xilinx boot ROM
u-boot/u-boot.elf: u-boot/u-boot
	cp $? $@
	arm-xilinx-linux-gnueabi-strip $@

boot/BOOT.bin: scripts/fsbl.bif fpga/fsbl/clock/Release/clock.elf u-boot/u-boot.elf
	bootgen -image scripts/fsbl.bif -w -o boot/BOOT.bin

boot: fpga boot/BOOT.bin


######################################################################
#  Xilinx linux kernel build

# Pickup tools from u-boot in PATH
PATH := ${PATH}:${PWD}/u-boot/tools

linux/.config:
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- xilinx_zynq_defconfig

linux/arch/arm/boot/uImage: linux/.config
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- olddefconfig
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- UIMAGE_LOADADDR=0x8000 uImage

linux: linux/arch/arm/boot/uImage


######################################################################
debug:
	@echo PATH=${PATH}
	@echo PWD=${PWD}
