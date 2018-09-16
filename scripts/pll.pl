#!/usr/bin/perl

use Getopt::Std;
use Time::HiRes;
use strict;

$0 =~ s:^.*/::g;

my $g_algo = 0;
my $g_init = 0;
my $g_sim  = 0;

my $pfd_reg     = 0x80600110;
my $fd_reg      = 0x80600114;
my $vc_reg      = 0x80600124;
my $ppscnt_reg  = 0x80600118;

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
	if ($addr == $fd_reg) {
	    return (($g_pos[2] - $g_pos[1]) & 0xffffffff);
	} else {
	    return ($g_pos[2] & 0xffffffff);
	}
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


sub wait_for_gps
{
    my $pps_cnt = 0;
    my $val;
    my $i;
    my $diff = 0;

    for ($i = 0; $i < 600; $i++) {
	$val = peek($ppscnt_reg);
	if ($val != $pps_cnt) {
	    $diff++;
	}
	if ($diff > 10) {
	    return;
	}
	printf ("# %d  %d\n", $i, $val);
	$pps_cnt = $val;

	sleep(1);
    }
}


sub loworder
{
    my $mode     = 0;
    my $hold     = 0;

    my $vc       = 0.0;
    my $residual = 0.0;

    # my $alpha1   = 1.0;
    # my $gain1    = 10.0;
    # my $alpha2   = 1.0;
    # my $gain2    = 0.015;
    # my $gain3    = 1.0;

    my $alpha1   = 0.3;
    my $gain1    = 10.0;
    my $alpha2   = 1.0;
    my $gain2    = 0.007;
    my $gain3    = 1.0;

    # my $alpha1   = 0.3 / 10.0;
    # my $gain1    = 10.0;
    # my $alpha2   = 1.0;
    # my $gain2    = 0.007 / 10.0;
    # my $gain3    = 1.0;

    my $pfd_raw;
    my $pfd;
    my $fd_raw;
    my $fd;
    my $error;
    my $val;
#    my $last_vc;
    my $microseconds;
    my $tmp;
    my $i;
    my $status;
    my $lock_cnt;

    
    for ($i = 0; $i < 3; $i++) {
	$pfd_raw  = peek($pfd_reg);
	$pfd      = $pfd_raw;
	$pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);
	$val      = peek($vc_reg);
	printf ("# 0x%08x 0 %10.0f 0 0 0 0 0\n", $pfd_raw, $pfd);
	if (abs($pfd) > 5400000) {
	    printf ("# Resetting PFD\n");
	    poke($vc_reg, $val | 0x300000);
	    sleep (3);
	}
    }

    while (1) {

	# Read Phase Frequency Dector
	# Phase error step 2*pi/100e6, Kd = 100e6
	$pfd_raw  = peek($pfd_reg);
	$fd_raw   = peek($fd_reg);
	$pfd      = $pfd_raw;
	$pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);
	$fd       = $fd_raw;
	$fd      -= (0x80000000 * 2.0) if ($fd >= 0x80000000);

	# Gain
	$error    = $error * ( 1.0 - $alpha1) + $pfd * $gain1 * $alpha1;

	# Filter
#	$last_vc  = $vc;
	$vc       = $vc * (1.0 - $alpha2) + $error * $alpha2 + $residual;
#	if (abs($fd) < 10) {
#	    $residual += $error * 0.1;
	    $residual += $error * $gain2;
#	}	    
	
#	$vc       = $vc + $error * $alpha2;

	$val      = int($vc * $gain3 + 32768);

	# Clamp
	if ($val > 65535) {
	    $val = 65535;
	    $vc  = 32767.0 / $gain3;
	} elsif ($val < 0) {
	    $val = 0;
	    $vc  = -32768.0 / $gain3;
	}

        $status   = peek($vc_reg);
	poke($vc_reg, $val);

	printf("0x%08x  0x%08x  %3.0f %3.0f  %10f  %12f %12f  0x%04x  %d %d %d\n", 
	       $pfd_raw, $fd_raw, $pfd, $fd, $error, $residual, $vc, $val,
	       $status & 0x00800000 ? 1 : 0, $lock_cnt, $mode);

	if ($pfd == 0) {
	    $lock_cnt++;
	} else {
	    $lock_cnt = 0;
	}

	# Switch time constants when we are in lock
	if ($lock_cnt > 20) {
	    $alpha1   = 0.3 / 10.0;
	    $gain1    = 10.0;
	    $alpha2   = 1.0;
	    $gain2    = 0.007 / 10.0;
	    $gain3    = 1.0;
	    $mode     = 1;
	} elsif (abs($pfd) > 10) {
	    $alpha1   = 0.3;
	    $gain1    = 10.0;
	    $alpha2   = 1.0;
	    $gain2    = 0.007;
	    $gain3    = 1.0;
	    $mode     = 0;
	}

	($tmp, $microseconds) = Time::HiRes::gettimeofday;
	Time::HiRes::usleep(1000000 - $microseconds + 200000) if (!$g_sim);
    }
}



getopts('a:his');
$g_algo = $Getopt::Std::opt_a if ($Getopt::Std::opt_a);
$g_init = 1 if ($Getopt::Std::opt_i);
$g_sim  = 1 if ($Getopt::Std::opt_s);
usage("")   if $Getopt::Std::opt_h;


init_pll;

wait_for_gps;

if ($g_algo == 0) {
    loworder;
}

