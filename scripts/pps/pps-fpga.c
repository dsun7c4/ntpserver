/*
 * pps-fpga.c -- PPS client driver using custom FPGA
 *
 *
 * Copyright (C) 2017 Daniel Sun  <dcsun88osh@gmail.com>
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

#define PPS_FPGA_NAME "pps-fpga"
#define pr_fmt(fmt) PPS_FPGA_NAME ": " fmt

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/pps_kernel.h>
#include <linux/io.h>

#define FPGA_BASE_ADDR       0x80600000
#define FPGA_BASE_ADDR_SIZE  0x2000
#define FPGA_PPS_IRQ_ENABLE  0x128
#define FPGA_PPS_IRQ_STATUS  0x12c
#define FGPA_PPS_IRQ_TSC     0x00000001
#define FGPA_PPS_IRQ_GPS     0x00000002
#define FGPA_PPS_IRQ         0x80000000

/* Info for each registered platform device */
static struct pps_fpga_device_data {
	int irq;			/* IRQ used as PPS source */
	struct pps_device *pps;		/* PPS source device */
	struct pps_source_info info;	/* PPS source information */
        void __iomem *fpga_base;
} fpga;

/*
 * Report the PPS event
 */

static irqreturn_t pps_fpga_irq_handler(int irq, void *data)
{
	struct pps_event_time ts;
	u32 status;

	/* Get the time stamp first */
	pps_get_ts(&ts);

	/* Check IRQ status is from pps */
	status = readl_relaxed(fpga.fpga_base + FPGA_PPS_IRQ_STATUS);
	if (!(status & FGPA_PPS_IRQ)) {
	    return IRQ_NONE;
	}

	/* Clear IRQ */
	writel_relaxed(status, fpga.fpga_base + FPGA_PPS_IRQ_STATUS);

	/* Generate PPS event */
	pps_event(fpga.pps, &ts, PPS_CAPTUREASSERT, NULL);

	return IRQ_HANDLED;
}

static int pps_fpga_init(void)
{
	int ret;
	int pps_default_params;
	u32 status;
	/* struct device_node *np = pdev->dev.of_node; */

	printk(KERN_ALERT "%s:%d\n", __FUNCTION__, __LINE__);

	/* FPGA base address */
	fpga.fpga_base = ioremap(FPGA_BASE_ADDR, FPGA_BASE_ADDR_SIZE);
	if (!fpga.fpga_base) {
		printk(KERN_ALERT "invalid base address: 0x%p\n",
		       (void *)FPGA_BASE_ADDR);
		return -EINVAL;
	}

	printk(KERN_ALERT "%s:%d base addr: 0x%p\n", __FUNCTION__, __LINE__,
	       fpga.fpga_base);

	/* IRQ setup */
	fpga.irq = 64;
	status = readl_relaxed(fpga.fpga_base + FPGA_PPS_IRQ_ENABLE);
	status = (status & ~(FGPA_PPS_IRQ_TSC | FGPA_PPS_IRQ_GPS)) |
	         FGPA_PPS_IRQ_TSC;
	writel_relaxed(status, fpga.fpga_base + FPGA_PPS_IRQ_ENABLE);

	printk(KERN_ALERT "%s:%d enable: 0x%x\n", __FUNCTION__, __LINE__,
	       status);

	/* Clear IRQ */
	status = readl_relaxed(fpga.fpga_base + FPGA_PPS_IRQ_STATUS);
	writel_relaxed(status, fpga.fpga_base + FPGA_PPS_IRQ_STATUS);
	printk(KERN_ALERT "%s:%d enable: 0x%x\n", __FUNCTION__, __LINE__,
	       status);

	/* initialize PPS specific parts of the bookkeeping data structure. */
	fpga.info.mode = PPS_CAPTUREASSERT | PPS_OFFSETASSERT |
	    PPS_ECHOASSERT | PPS_CANWAIT | PPS_TSFMT_TSPEC;
	fpga.info.owner = THIS_MODULE;
	snprintf(fpga.info.name, PPS_MAX_NAME_LEN - 1, "%s",
		 PPS_FPGA_NAME);

	/* register PPS source */
	pps_default_params = PPS_CAPTUREASSERT | PPS_OFFSETASSERT;

	fpga.pps = pps_register_source(&fpga.info, pps_default_params);
	if (fpga.pps == NULL) {
	        printk(KERN_ALERT "failed to register IRQ %d as PPS source\n",
		       fpga.irq);
		goto pps_reg_err;
	}

	/* register IRQ interrupt handler */
	ret = request_irq(fpga.irq, pps_fpga_irq_handler,
			IRQF_TRIGGER_HIGH, fpga.info.name, &fpga);
	if (ret) {
	        printk(KERN_ALERT "failed to acquire IRQ %d\n", fpga.irq);
		goto irq_reg_err;
	}

	printk(KERN_ALERT "Registered IRQ %d as PPS source\n",
	       fpga.irq);

	return 0;

 irq_reg_err:
	pps_unregister_source(fpga.pps);

 pps_reg_err:
	iounmap(fpga.fpga_base);

	return -EINVAL;
}

static void pps_fpga_exit(void)
{
	free_irq(fpga.irq, &fpga);
	pps_unregister_source(fpga.pps);
	iounmap(fpga.fpga_base);
	printk(KERN_ALERT "removed IRQ %d as PPS source\n", fpga.irq);
}

module_init(pps_fpga_init);
module_exit(pps_fpga_exit);

MODULE_AUTHOR("Daniel Sun  <dcsun88osh@gmail.com>");
MODULE_DESCRIPTION("Use custom FPGA as PPS source");
MODULE_LICENSE("GPL");
MODULE_VERSION("1.0.0");
