/*
 * ocxo.c
 *
 * Read the 100MHz OCXO tsc counter locked to GPS 1 PPS.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/clocksource.h>


#define OCXO_BASE_ADDR       0x80600000
#define OCXO_BASE_ADDR_SIZE  0x2000
#define OCXO_CLK_HZ          100000000    /* 100 MHz */
#define OCXO_COUNTER0	     0x100
#define OCXO_COUNTER1	     0x104


/*
 *
 */
static void __iomem *ocxo_base;

#if 0
static DEFINE_SPINLOCK(ocxo_lock);
/*
 * To get the value from the OCXO Counter register proceed as follows:
 * 1. Lock the access to the tsc registers.
 * 2. Read the lower 32-bit timer counter register (HW latches upper regisger).
 * 3. Read the upper 32-bit timer counter register.
 * 4. Unlock the access to the tsc registers
 */
static u64 ocxo_counter_read(void)
{
	u64 counter;
	u32 lower;
	u32 upper;

	spin_lock(&ocxo_lock);
	lower = readl_relaxed(ocxo_base + OCXO_COUNTER0);
	upper = readl_relaxed(ocxo_base + OCXO_COUNTER1);
	spin_unlock(&ocxo_lock);

	counter = upper;
	counter <<= 32;
	counter |= lower;
	return counter;
}
#endif

/*
 * To ensure that updates to comparator value register do not set the
 * Interrupt Status Register proceed as follows:
 * 1. Clear the Comp Enable bit in the Timer Control Register.
 * 2. Write the lower 32-bit Comparator Value Register.
 * 3. Write the upper 32-bit Comparator Value Register.
 * 4. Set the Comp Enable bit and, if necessary, the IRQ enable bit.
 */
static u64 ocxo_counter_read(void)
{
	u64 counter;
	u32 lower;
	u32 upper, old_upper;

	upper = readl_relaxed(ocxo_base + OCXO_COUNTER1);
	do {
		old_upper = upper;
		lower = readl_relaxed(ocxo_base + OCXO_COUNTER0);
		upper = readl_relaxed(ocxo_base + OCXO_COUNTER1);
	} while (upper != old_upper);

	counter = upper;
	counter <<= 32;
	counter |= lower;
	return counter;
}

static cycle_t ocxo_clocksource_read(struct clocksource *cs)
{
	return ocxo_counter_read();
}

static struct clocksource ocxo_clocksource = {
	.name	= "ocxo_tsc",
	.rating	= 301,
	.read	= ocxo_clocksource_read,
	.mask	= CLOCKSOURCE_MASK(64),
	.flags	= CLOCK_SOURCE_IS_CONTINUOUS,
};

static int __init ocxo_tsc_init(void)
{
	/* struct clk *ocxo_clk; */
	int err = 0;

	ocxo_base = ioremap(OCXO_BASE_ADDR, OCXO_BASE_ADDR_SIZE);
	if (!ocxo_base) {
		pr_warn("ocxo: invalid base address\n");
		return 1;
	}

	err = clocksource_register_hz(&ocxo_clocksource, OCXO_CLK_HZ);
	if (err) {
	    pr_warn("ocxo: Failed to register clocksource\n");
	    goto out_unmap;
	}

	return 0;

out_unmap:
	iounmap(ocxo_base);
	WARN(err, "OCXO tsc register failed (%d)\n", err);
	return 1;
}

static void __exit ocxo_tsc_exit(void)
{
    clocksource_unregister(&ocxo_clocksource);
    iounmap(ocxo_base);
 }

module_init(ocxo_tsc_init);
module_exit(ocxo_tsc_exit);

MODULE_AUTHOR("dcsun88osh@gmail.com");
MODULE_DESCRIPTION("Clocksource driver for OCXO tsc");
MODULE_LICENSE("GPL");
