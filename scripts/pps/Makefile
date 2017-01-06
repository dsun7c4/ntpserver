
# To build modules outside of the kernel tree, we run "make"
# in the kernel source tree; the Makefile these then includes this
# Makefile once again.
# This conditional selects whether we are being included from the
# kernel Makefile or not.
ifeq ($(KERNELRELEASE),)

    # Assume the source tree is where the running kernel was built
    # You should set KERNELDIR in the environment if it's elsewhere
    KERNELDIR ?= /home/save1/ntpserver/linux
    # The current directory is passed to sub-makes as argument
    PWD := $(shell pwd)

modules:
	$(MAKE) ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- -C $(KERNELDIR) M=$(PWD) modules

clean:
	$(MAKE) ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- -C $(KERNELDIR) M=$(PWD) clean

.PHONY: modules clean

else
    # called from kernel build system: just declare what our modules are
    obj-m := pps-fpga.o

endif


