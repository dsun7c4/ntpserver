
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
#  Xilinx linux kernel build

# Pickup tools from u-boot in PATH
PATH := ${PATH}:${PWD}/u-boot/tools

linux/arch/arm/boot/uImage:
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- xilinx_zynq_defconfig
	${MAKE} -C linux ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- UIMAGE_LOADADDR=0x8000 uImage

linux: linux/arch/arm/boot/uImage


######################################################################
debug:
	@echo PATH=${PATH}
	@echo PWD=${PWD}
