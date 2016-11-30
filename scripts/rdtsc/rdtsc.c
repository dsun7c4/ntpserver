/*
 * TSC read time measurement
 * 
 * Measure the time it takes to read the two tsc registers in the fpga.
 * 
 * Licensed under GPLv2 or later
 *
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>

#define LOOP 1000000

int main(int argc, char *argv[])
{
	int fd;
	void *ptr;
	unsigned addr, page_addr, page_offset;
	unsigned page_size=sysconf(_SC_PAGESIZE);
	volatile unsigned *tsc_l, *tsc_h;
	long long *tick;
	unsigned  reg;
	unsigned long long tmp;
	int i;

	fd=open("/dev/mem",O_RDONLY);
	if(fd<1) {
		perror(argv[0]);
		exit(-1);
	}

	addr=0x80600100;
	page_addr=(addr & ~(page_size-1));
	page_offset=addr-page_addr;

	ptr=mmap(NULL,page_size,PROT_READ,MAP_SHARED,fd,(addr & ~(page_size-1)));
	if((int)ptr==-1) {
		perror(argv[0]);
		exit(-1);
	}

	tsc_l = (unsigned *)(ptr+page_offset);
	tsc_h = (unsigned *)(ptr+page_offset + 4);
	tick  = malloc(LOOP * sizeof(*tick));

	for (i = 0; i < LOOP; i++) {
	    reg = *tsc_l;
	    tmp = *tsc_h;
	    tmp = (tmp << 32) | reg;
	    tick[i] = tmp;
	    /* This loop takes ~550 ns per iteration */
	}

	for (i = 0; i < LOOP; i++) {
	    printf("0x%016llx\n", tick[i]);
	}

	/* 2.394 seconds for LOOP reads of the tsc and dump */

	return 0;
}


