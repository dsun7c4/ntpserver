#!/usr/bin/perl

use Getopt::Std;
use strict;

$0 =~ s:^.*/::g;

my $g_init = 0;

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

sub peek
{
    my($addr) = @_;
    my $val;

    $val = `/root/bin/peek $addr`;

    return (hex($val));
}

sub poke
{
    my($addr, $val) = @_;
    my $ret;

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



getopts('hi');
$g_init = 1 if ($Getopt::Std::opt_i);
usage("")   if $Getopt::Std::opt_h;

if ($g_init) {
    init_pll;
}


my $vc      = 0.0;
my $pfd_reg = 0x80600008;
my $vc_reg  = 0x80600010;
my $alpha1  = 1.0;
my $gain1   = 1.0;
my $alpha2  = 0.2;
my $gain2   = 1.0;

while (1) {
    my $pfd_raw;
    my $pfd;
    my $error;
    my $val;

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
    $vc = $vc * (1.0 - $alpha2) + $error * $alpha2;
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

    printf("0x%08x  %.0f  %f  %f  0x%04x\n", $pfd_raw, $pfd, $error, $vc, $val);

    sleep(1);
}
