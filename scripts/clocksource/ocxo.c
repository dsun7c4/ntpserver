/*
 * ocxo.c
 *
 * Read the 100MHz OCXO tsc counter locked to GPS 1 PPS.
 *
 * Copyright (C) 2017,2021 Daniel Sun  <dsun7c4osh@gmail.com>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the Free Software
 *   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/clocksource.h>
#include <linux/spinlock.h>

#define OCXO_BASE_ADDR       0x80600000
#define OCXO_BASE_ADDR_SIZE  0x2000
#define OCXO_CLK_HZ          100000000    /* 100 MHz */
#define OCXO_COUNTER0        0x100
#define OCXO_COUNTER1        0x104


/*
 *
 */
static void __iomem *ocxo_base;

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
    unsigned long flags;
    u64 counter;
    u32 lower;
    u32 upper;

    spin_lock_irqsave(&ocxo_lock, flags);
    lower = readl(ocxo_base + OCXO_COUNTER0);
    upper = readl_relaxed(ocxo_base + OCXO_COUNTER1);
    spin_unlock_irqrestore(&ocxo_lock, flags);

    counter = upper;
    counter <<= 32;
    counter |= lower;
    return counter;
}


static u64 ocxo_clocksource_read(struct clocksource *cs)
{
    return ocxo_counter_read();
}

static struct clocksource ocxo_clocksource = {
    .name       = "ocxo_tsc",
    .rating     = 301,
    .read       = ocxo_clocksource_read,
    .mask       = CLOCKSOURCE_MASK(64),
    .flags      = CLOCK_SOURCE_IS_CONTINUOUS,
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
    pr_warn("OCXO tsc register failed (%d)\n", err);
    return 1;
}

static void __exit ocxo_tsc_exit(void)
{
    clocksource_unregister(&ocxo_clocksource);
    iounmap(ocxo_base);
}

module_init(ocxo_tsc_init);
module_exit(ocxo_tsc_exit);

MODULE_AUTHOR("dsun7c4osh@gmail.com");
MODULE_DESCRIPTION("Clocksource driver for OCXO tsc");
MODULE_LICENSE("GPL");
