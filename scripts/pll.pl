#!/usr/bin/perl

use Getopt::Std;
use strict;

$0 =~ s:^.*/::g;

my $g_algo = 0;
my $g_init = 0;
my $g_sim  = 0;

sub usage
{
   my($msg) = @_;

        print "ERROR: $msg\n" if $msg;

        die <<EOF;
Use:
   $0 [options]

Read sensors

Options:
   -h             This message.
   -i             Initialize DAC driver
EOF

}

my $g_pll_freq = 10.0e6;
my @g_pos      = (50e6, 50e6, 50e6);

sub peek
{
    my($addr) = @_;
    my $val;

    if ($g_sim) {
	return ($g_pos[2] & 0xffffffff);
    }

    $val = `/root/bin/peek $addr`;

    return (hex($val));
}

sub poke
{
    my($addr, $val) = @_;
    my $ret;

    if ($g_sim) {
	my $step;

	$g_pos[3] = $g_pos[2];
	$g_pos[2] = $g_pos[1];
	$g_pos[1] = $g_pos[0];

	$step = -(18325)/65535 * $val + 9800;
	#printf("%d\n", $step);
	$g_pos[0] += $step;

	if ($g_pos[0] > 100e6) { $g_pos[0] -= 100e6; }
	elsif ($g_pos[0] < -100e6) { $g_pos[0] += 100e6; }

	return (0);
    }

    $ret = `/root/bin/poke $addr $val`;

    return ($ret);
}

sub i2cget
{
    my($bus, $addr, $reg) = @_;
    my $val;

    $val = `i2cget -y $bus $addr $reg`;

    return (hex($val));
}

sub i2cset
{
    my($bus, $addr, $reg, $val) = @_;
    my $ret;

    $val = `i2cset -y $bus $addr $reg $val`;

    return ($ret);
}

sub init_pll
{
    my $val;
    my $gpio = 0x41200000;

    $val = peek($gpio);

    $val = $val | 0xc0;

    poke($gpio, $val);
}


sub loworder
{
    my $vc      = 0.0;
    my $pfd_reg = 0x80600008;
    my $vc_reg  = 0x80600010;
    my $alpha1  = 1.0;
    my $gain1   = 1.0;
    my $alpha2  = 1.0;
    my $gain2   = 1.0;
    my $residual = 0.0;

    my $pfd_raw;
    my $pfd;
    my $error;
    my $val;
    my $last_vc;

    while (1) {

	# Read Phase Frequency Dector
	# Phase error step 2*pi/100e6, Kd = 100e6
	$pfd_raw  = peek($pfd_reg);
	$pfd      = $pfd_raw;
	$pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);

	# Gain
	$error   = $error * ( 1.0 - $alpha1) + $pfd * $gain1 * $alpha1;

	# Clamp
	# $error   = 32767 if ($error > 32767);
	# $error   = -32768 if ($error < -32768);

	# Filter
	$last_vc = $vc;
	$vc = $vc * (1.0 - $alpha2) + $error * $alpha2 + $residual;
	if (abs($vc - $last_vc) < 10) {
	    $residual += $error * 0.1;
	}	    
	
	#$vc = $vc + $error * $alpha2;

	$val = int($vc * $gain2 + 32768);
	if ($val > 65535) {
	    $val = 65535;
	    $vc  = 32767.0 / $gain2;
	} elsif ($val < 0) {
	    $val = 0;
	    $vc  = -32768.0 / $gain2;
	}

	poke($vc_reg, $val);

	printf("0x%08x  %.0f  %f  %f  0x%04x  %f\n", $pfd_raw, $pfd, $error, $vc, $val, $residual);

	sleep(1) if (!$g_sim);
    }
}


sub passive
{
    my $vc;
    my $pfd_reg = 0x80600008;
    my $vc_reg  = 0x80600010;
    my $r1      = 1.0;
    my $r2      = 1.0;
    my $c1      = 3e-3;
    my $vc1     = 36193.0;
    my $tc      = 1.0 / (($r1 + $r2) * $c1);

    my $pfd_raw;
    my $pfd;
    my $t;
    my $va;
    my $val;

    while (1) {

	# Read Phase Frequency Dector
	# Phase error step 2*pi/100e6, Kd = 100e6
	$pfd_raw  = peek($pfd_reg);
	$pfd      = $pfd_raw;
	$pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);

	# Passive lag filter
	$t   = abs($pfd) * 10e-9;
	$va  = $pfd > 0 ? 65534.0 : 1.0;
	$vc1 = $va * (1 - exp(-$t * $tc)) + $vc1 * exp (-$t * $tc);

	# Control voltage
	#$vc = (65535.0 - $vc1) / ($r1 + $r2) * $r2 + $vc1;
	$vc = $vc1;

	# DAC: 0 p: 9100 f: 0.99990900828   DAC: 65535 p: 9470 f: 1.00009470897
	# K0 = 2.83361089494e-9
	$val = int($vc);

	poke($vc_reg, $val);

	printf("0x%08x  %.0f  %f  %f  0x%04x\n", $pfd_raw, $pfd, $vc1, $vc, $val);

	sleep(1) if (!$g_sim);
    }
}


sub subsample
{
    my $vc;
    my $pfd_reg = 0x80600008;
    my $vc_reg  = 0x80600010;
    my $r1      = 2.0;
    my $r2      = 1.0;
    my $c1      = 1.0e2;
    my $vc1     = 36193.0;
    my $tc      = 1.0 / (($r1 + $r2) * $c1);
    my $pfd_acc = 0.0;
    my $cnt     = 0;
    my $gainv   = 64.0;

    my $pfd_raw;
    my $pfd;
    my $t;
    my $va;
    my $val;

    while (1) {

	# Read Phase Frequency Dector
	# Phase error step 2*pi/100e6, Kd = 100e6
	$pfd_raw  = peek($pfd_reg);
	$pfd      = $pfd_raw;
	$pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);
	$pfd_acc += $pfd;
	$cnt++;

	if (($cnt % 16) == 0) {
	    # Passive lag filter
	    $t   = abs($pfd) * 10e-9;
	    $va  = $pfd_acc > 0 ? 32767.0 / $gainv: -32767.0 / $gainv;
	    $vc1 = $va * (1 - exp(-$t * $tc)) + $vc1 * exp (-$t * $tc);

	    # Control voltage
	    #$vc = (65535.0 - $vc1) / ($r1 + $r2) * $r2 + $vc1;
	    $vc = ($vc1 * $gainv)  + 32768;

	    # DAC: 0 p: 9100 f: 0.99990900828   DAC: 65535 p: 9470 f: 1.00009470897
	    # K0 = 2.83361089494e-9
	    $val = int($vc);

	    printf("0x%08x  %10.0f  %12f  %12f  0x%04x\n", $pfd_raw, $pfd_acc, $vc1, $vc, $val);
	    $pfd_acc = 0.0;
	}

	poke($vc_reg, $val);

	#printf("0x%08x  %10.0f  %12f  %12f  0x%04x\n", $pfd_raw, $pfd_acc, $vc1, $vc, $val) if ($cnt);
	return if ($g_sim && $cnt > 3600);

	sleep(1) if (!$g_sim);
    }
}


sub state
{
    my $pfd_reg = 0x80600008;
    my $vc_reg  = 0x80600010;
    my $pfd_d   = 0.0;
    my $cnt     = 0;
    my $perr    = 0.0;

    my $pfd_raw;
    my $pfd;
    my $vc;
    my $val;

    while (1) {

	# Read Phase Frequency Dector
	# Phase error step 2*pi/100e6, Kd = 100e6
	$pfd_d    = $pfd;
	$pfd_raw  = peek($pfd_reg);
	$pfd      = $pfd_raw;
	$pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);
	$perr     = $pfd - $pfd_d;
	$cnt++;
	
	
	$val = 0x8000;

	printf("0x%08x  %10.0f  %12f  %12f  0x%04x\n", $pfd_raw, $pfd, $perr, $vc, $val);

	poke($vc_reg, $val);

	sleep(1) if (!$g_sim);
    }
}


getopts('a:his');
$g_algo = $Getopt::Std::opt_a if ($Getopt::Std::opt_a);
$g_init = 1 if ($Getopt::Std::opt_i);
$g_sim  = 1 if ($Getopt::Std::opt_s);
usage("")   if $Getopt::Std::opt_h;

if ($g_init) {
    init_pll;
}

if ($g_algo == 0) {
    loworder;
} elsif ($g_algo == 1) {
    passive;
} elsif ($g_algo == 2) {
    subsample;
} elsif ($g_algo == 3) {
    state;
}

