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

#include <linux/platform_device.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/interrupt.h>
#include <linux/of.h>
#include <linux/module.h>
#include <linux/pps_kernel.h>
#include <linux/io.h>

#define FPGA_BASE_ADDR       0x80600000
#define FPGA_BASE_ADDR_SIZE  0x2000
#define FPGA_CLK_NS          10    /* 100 MHz */
#define FPGA_TSC_LSW         0x100
#define FPGA_TSC_MSW         0x104
#define FPGA_TSC_IRQ_LSW     0x108
#define FPGA_TSC_IRQ_MSW     0x10c
#define FPGA_PPS_IRQ_ENABLE  0x128
#define FPGA_PPS_IRQ_STATUS  0x12c
#define FGPA_PPS_IRQ_TSC     0x00000001
#define FGPA_PPS_IRQ_GPS     0x00000002
#define FGPA_PPS_IRQ         0x80000000

/* Device info */
struct pps_fpga_device_data {
    int irq;                        /* IRQ used as PPS source */
    struct pps_device *pps;         /* PPS source device */
    struct pps_source_info info;    /* PPS source information */
    void __iomem *fpga_base;
};

/*
 * Report the PPS event
 */

static irqreturn_t pps_fpga_irq_handler(int irq, void *data)
{
    struct pps_fpga_device_data *fpga;
    struct pps_event_time ts;
    u32 now;
    u32 irq_cycle;
    u32 status;

    fpga = data;

    /* Read the time stamp counter for interrupt latency measurement */
    now = readl_relaxed(fpga->fpga_base + FPGA_TSC_LSW);

    /* Get the time stamp first */
    pps_get_ts(&ts);

    /* Check IRQ status is from pps */
    status = readl_relaxed(fpga->fpga_base + FPGA_PPS_IRQ_STATUS);
    if (!(status & FGPA_PPS_IRQ)) {
	return IRQ_NONE;
    }

    /* Clear IRQ */
    writel_relaxed(status, fpga->fpga_base + FPGA_PPS_IRQ_STATUS);

    /* The time stamp counter at the interrupt */
    irq_cycle = readl_relaxed(fpga->fpga_base + FPGA_TSC_IRQ_LSW);
        
    /* Set the pps offset to the measured interrupt latencey */
    fpga->pps->params.assert_off_tu.sec  = 0;
    fpga->pps->params.assert_off_tu.nsec = - ((u32) (now - irq_cycle)) * FPGA_CLK_NS;

    /* Generate PPS event */
    pps_event(fpga->pps, &ts, PPS_CAPTUREASSERT, NULL);

    return IRQ_HANDLED;
}

static int pps_fpga_probe(struct platform_device *pdev)
{
    struct pps_fpga_device_data *fpga;
    struct resource *res;
    int irq;
    int ret;
    int pps_default_params;
    u32 status;

    fpga = devm_kzalloc(&pdev->dev, sizeof(*fpga), GFP_KERNEL);
    if (!fpga)
	return -ENOMEM;
    platform_set_drvdata(pdev, fpga);

    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    if (!res) {
	return -ENODEV;
    }
    irq = platform_get_irq(pdev, 0);
    if (irq <= 0) {
	return -ENXIO;
    }

    dev_info(&pdev->dev, "%s:  Reg 0x%x-0x%x  irq: %d\n",
	     res->name, res->start, res->end, irq);

    /* FPGA base address */
    fpga->fpga_base = devm_ioremap_nocache(&pdev->dev, res->start, res->end - res->start + 1);
    if (!fpga->fpga_base) {
	dev_err(&pdev->dev, "Invalid base address: 0x%px\n", (void *)res->start);
	return -EINVAL;
    }


    /* IRQ setup */
    fpga->irq = irq;
    status = readl_relaxed(fpga->fpga_base + FPGA_PPS_IRQ_ENABLE);
    status = (status & ~(FGPA_PPS_IRQ_TSC | FGPA_PPS_IRQ_GPS)) |
	FGPA_PPS_IRQ_TSC;
    writel_relaxed(status, fpga->fpga_base + FPGA_PPS_IRQ_ENABLE);

    /* Clear IRQ */
    status = readl_relaxed(fpga->fpga_base + FPGA_PPS_IRQ_STATUS);
    writel_relaxed(status, fpga->fpga_base + FPGA_PPS_IRQ_STATUS);


    /* initialize PPS specific parts of the bookkeeping data structure. */
    fpga->info.mode = PPS_CAPTUREASSERT | PPS_OFFSETASSERT |
	PPS_ECHOASSERT | PPS_CANWAIT | PPS_TSFMT_TSPEC;
    fpga->info.owner = THIS_MODULE;
    snprintf(fpga->info.name, PPS_MAX_NAME_LEN - 1, "%s",
	     PPS_FPGA_NAME);
    pps_default_params = PPS_CAPTUREASSERT | PPS_OFFSETASSERT;

    /* register PPS source */
    fpga->pps = pps_register_source(&fpga->info, pps_default_params);
    if (fpga->pps == NULL) {
	dev_err(&pdev->dev, "failed to register IRQ %d as PPS source\n",
		fpga->irq);
	return -EINVAL;
    }

    /* register IRQ interrupt handler */
    ret = request_irq(fpga->irq, pps_fpga_irq_handler,
		      IRQF_TRIGGER_HIGH, fpga->info.name, fpga);
    if (ret) {
	dev_err(&pdev->dev, "Failed to acquire IRQ %d\n", fpga->irq);
	goto irq_reg_err;
    }

    return 0;

 irq_reg_err:
    pps_unregister_source(fpga->pps);

    return -EINVAL;
}

static int pps_fpga_remove(struct platform_device *pdev)
{
    struct pps_fpga_device_data *fpga;

    fpga = platform_get_drvdata(pdev);

    free_irq(fpga->irq, fpga);
    pps_unregister_source(fpga->pps);
    dev_info(&pdev->dev, "removed IRQ %d as PPS source\n", fpga->irq);

    return 0;
}

static const struct of_device_id pps_fpga_of_match[] = {
	{ .compatible = "fpga,ocxo-pps-0.90"},
	{}
};
MODULE_DEVICE_TABLE(of, pps_fpga_of_match);

static struct platform_driver pps_fpga_platform_driver = {
	.probe   = pps_fpga_probe,
	.remove  = pps_fpga_remove,
	.driver  = {
		.name = PPS_FPGA_NAME,
		.of_match_table = pps_fpga_of_match,
		},
};

module_platform_driver(pps_fpga_platform_driver);

MODULE_AUTHOR("Daniel Sun  <dcsun88osh@gmail.com>");
MODULE_DESCRIPTION("Use custom FPGA as PPS source");
MODULE_LICENSE("GPL");
MODULE_VERSION("0.9.0");
