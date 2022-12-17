#!/usr/bin/perl

use Getopt::Std;
use Time::HiRes;
use Math::Trig;
use strict;

$0 =~ s:^.*/::g;

my $g_algo = 0;
my $g_init = 0;
my $g_sim  = 0;

my $pfd_reg     = 0x80600110;
my $fd_reg      = 0x80600114;
my $ppscnt_reg  = 0x80600118;
my $ctime_reg   = 0x8060011c;
my $stime_reg   = 0x80600120;
my $vc_reg      = 0x80600124;

my $max_hold_time = 900;  # 15 minutes
my $min_hold_time = 30;   # 30 seconds

# PFD gain
my $g_Kd          = 100e6 / (2.0 * pi);

# VCO gain, measured value for PMOD VCOCXO
my $g_K0          = 0.0216329414791739 * 1e-9 * 2.0 * pi;
# VCO gain, measured value for clock VCOCXO
#my $g_K0          = 0.0142881192851401 * 1e-9 * 2.0 * pi;


sub usage
{
   my ($msg) = @_;

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
    my ($addr) = @_;
    my $val;

    if ($g_sim) {
        if ($addr == $fd_reg) {
            return (($g_pos[2] - $g_pos[1]) & 0xffffffff);
        } else {
            return ($g_pos[2] & 0xffffffff);
        }
    }

    $val = `/root/bin/peek $addr`;
    if ($? != 0) {
        printf ("# peek(0x%x): returned %d, %d\n",
                $addr,
                $? >> 8, $? & 127);
    }

    return (hex($val));
}

sub poke
{
    my ($addr, $val) = @_;
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
    if ($? != 0) {
        printf ("# poke(0x%x, 0x%x): returned %d, %d\n",
                $addr, $val,
                $? >> 8, $? & 127);
    }

    return ($ret);
}

sub i2cget
{
    my ($bus, $addr, $reg, $mode) = @_;
    my $val;
    my $i;

    # Retry one time on read, in case of read failure on temperature sensor
    for ($i = 0; $i < 2; $i++) {
        $val = `i2cget -y $bus $addr $reg $mode`;
        if ($? != 0) {
            printf ("# i2cget(%d, 0x%x, 0x%x, %s): returned %d, %d\n",
                    $bus, $addr, $reg, $mode,
                    $? >> 8, $? & 127);
        } else {
            last;
        }
    }

    return (hex($val));
}

sub i2cset
{
    my ($bus, $addr, $reg, $val) = @_;
    my $ret;

    $val = `i2cset -y $bus $addr $reg $val`;
    if ($? != 0) {
        printf ("# i2cset(%d, 0x%x, 0x%x, 0x%x): returned %d, %d\n",
                $bus, $addr, $reg, $val,
                $? >> 8, $? & 127);
    }

    return ($ret);
}

sub read_xadc
{
    my $base = 0x43c00000;
    my $temp_raw;
    my $temp;

    $temp_raw = peek($base + 0x200) >> 4;
    $temp     = $temp_raw * 503.975 / 4096.0 - 273.15;

    return $temp;

}

sub init_ltc2990
{

    i2cset(1, 0x4c, 1, 0x19);
    i2cset(1, 0x4c, 2, 0);

}

sub read_ltc2990
{
    my $temp_raw_msb;
    my $temp_raw_lsb;
    my $temp_raw;
    my $temp;
    my $volt_raw_msb;
    my $volt_raw_lsb;
    my $volt_raw;
    my $volt;
    my $tint;
    my $iocxo;
    my $tocxo;

    $temp_raw      = i2cget(1, 0x4c, 4, "w");
    $temp_raw      = unpack("S>", pack("S", $temp_raw));
    $temp          = $temp_raw & 0x1fff;
    $temp          = $temp - 0x2000 if ($temp >= 0x1000);
    $tint          = $temp * 0.0625;

    $volt_raw      = i2cget(1, 0x4c, 6, "w");
    $volt_raw      = unpack("S>", pack("S", $volt_raw));
    $volt          = $volt_raw & 0x7fff;
    $volt         -= 0x8000 if ($volt >= 0x4000);
    $volt          = $volt * 19.42e-6;
    $iocxo         = $volt / 0.1;

    $temp_raw      = i2cget(1, 0x4c, 0xa, "w");
    $temp_raw      = unpack("S>", pack("S", $temp_raw));
    $temp          = $temp_raw & 0x1fff;
    $temp          = $temp - 0x2000 if ($temp >= 0x1000);
    $tocxo         = $temp * 0.0625;

    return ($tint, $iocxo, $tocxo);

}

sub init_adt7410
{

    i2cset(2, 0x48, 3, 0x80);
    i2cset(2, 0x49, 3, 0x80);

}

sub read_adt7410
{
    my $temp_raw;
    my $temp;
    my $tcpu;
    my $tedge;


    $temp_raw      = i2cget(2, 0x48, 0, "w");
    $temp_raw      = unpack("s>", pack("S", $temp_raw));
    $temp          = $temp_raw;
    $temp         -= 0x10000 if ($temp >= 0x8000);
    $tcpu          = $temp * 0.0078125;

    $temp_raw      = i2cget(2, 0x49, 0, "w");
    $temp_raw      = unpack("s>", pack("S", $temp_raw));
    $temp          = $temp_raw;
    $temp         -= 0x10000 if ($temp >= 0x8000);
    $tedge         = $temp * 0.0078125;

    return ($tcpu, $tedge);

}

sub init_sensors
{
    init_ltc2990;
    init_adt7410;

    # The first temperature read from the Xilinx xadc seems to return
    # a bogus value ie. 1045.231866
    read_xadc;
}

sub init_pll
{
    my $val;
    my $gpio = 0x41200000;

    $val = peek($gpio);

    $val = $val | 0xc0;

    poke($gpio, $val);
}

# Wait up to 10 minutes for 10 pps ticks from the GPS receiver
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

sub sensors
{
    my $temp;
    my $tcpu;
    my $tedge;
    my $tint;
    my $iocxo;
    my $tocxo;

    $temp                   = read_xadc;
    ($tcpu, $tedge)         = read_adt7410;
    ($tint, $iocxo, $tocxo) = read_ltc2990;

    return ($temp, $tint, $iocxo, $tocxo, $tcpu, $tedge);
}

sub set_time
{
    my ($epoc) = @_;
    my $c_time;
    my $sec;
    my $min;
    my $hour;
    my $other;
    my $set_x;

    # Get displayed time
    $c_time = peek($ctime_reg);

    # HMS time one second later
    ($sec, $min, $hour, $other) = localtime($epoc + 1);

    $set_x = sprintf("%02d%02d%02d", $hour, $min, $sec);
    poke($stime_reg, hex($set_x));

    printf("# Setting time from %08x to %s  %02d:%02d:%02d\n", $c_time, $set_x, $hour, $min, $sec);
}

# Compare the displayed time with the system TZ time and update the
# display if needed
sub display_rtc
{
    my $epoc;
    my $sec;
    my $min;
    my $hour;
    my $other;
    my $c_time;
    my $c_sec;
    my $c_min;
    my $c_hour;

    $epoc = time;

    ($sec, $min, $hour, $other) = localtime($epoc);
    $c_time = peek($ctime_reg);
    $c_hour =
        (($c_time >> 28) & 0xf) * 10 +
        (($c_time >> 24) & 0xf);
    if ($c_hour != $hour) {
        set_time($epoc);
    } else {
        $c_min =
            (($c_time >> 20) & 0xf) * 10 +
            (($c_time >> 16) & 0xf);
        if ($c_min != $min) {
            set_time($epoc);
        } else {
            $c_sec =
                (($c_time >> 12) & 0xf) * 10 +
                (($c_time >>  8) & 0xf);
            if ($c_sec != $sec) {
                set_time($epoc);
            }
        }
    }

}

# Initialize the PFD with initial control value
# Reset the PFD to jump into sync, takes too long to slew
# Set the display time
sub init_pfd
{
    my ($control) = @_;

    my $pfd_raw;
    my $pfd;
    my $val;
    my $i;

    poke($vc_reg, $control);
    sleep (1);

    for ($i = 0; $i < 3; $i++) {
        $pfd_raw  = peek($pfd_reg);
        $pfd      = $pfd_raw;
        $pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);
        $val      = peek($vc_reg);
        printf ("# PFD: 0x%08x %.0f 0x%04x\n", $pfd_raw, $pfd, $val);
        sleep (1);
    }

    # Reset the PFD
    printf ("# Resetting PFD\n");
    poke($vc_reg, $val | 0x300000);
    sleep (3);

    # Set the time after a PFD jump to align ms counters
    set_time(time);

}

# Read the PFD phase error, frequency error, and status
sub read_pfd
{
    my $pfd_raw;
    my $pfd;

    my $fd_raw;
    my $fd;

    my $status;

    # Read Phase Frequency Detector
    # Phase error step 2*pi/100e6, Kd = 100e6

    # Read phase error
    $pfd_raw  = peek($pfd_reg);
    $pfd      = $pfd_raw;
    $pfd     -= (0x80000000 * 2.0) if ($pfd >= 0x80000000);
    # Read frequency error (d/dt phase error)
    $fd_raw   = peek($fd_reg);
    $fd       = $fd_raw;
    $fd      -= (0x80000000 * 2.0) if ($fd >= 0x80000000);
    # Check PFD status, 1 = in re-sync mode
    $status   = peek($vc_reg) & 0x00800000 ? 1 : 0;

    return ($pfd, $fd, $status);

}

sub loworder
{
    my $mode     = 0;
    my $hold     = 0;
    my $wait     = 0;

    my $temp;
    my $tcpu;
    my $tedge;
    my $tint;
    my $iocxo;
    my $tocxo;

    my $vc       = 0.0;
    my $residual = 3584.0;

    my $alpha1   = 0.3;
    my $gain1    = 10.0;
    my $alpha2   = 1.0;
    my $gain2    = 0.007;
    my $gain3    = 1.0;

    my $pfd;
    my $pfd_last;
    my $fd;
    my $error;
    my $val;
    my $microseconds;
    my $tmp;
    my $i;
    my $status;
    my $lock_cnt  = 0;
    my $flock_cnt = 0;


    # Set the VCO to the residual value before resetting the PFD
    init_pfd(int($residual * $gain3 + 32768));

    while (1) {

        # Read Phase Frequency Detector
        # Phase error step 2*pi/100e6, Kd = 100e6
        $pfd_last = $pfd;

	($pfd, $fd, $status) = read_pfd;

        # Detect a large jump in phase or dropped pps from GPS when in
        # slow response mode
        if (($mode == 1 && abs($pfd - $pfd_last) > 10) || $status) {
	    if ($hold == 0) {
		# Clear error
		$error    = 0.0;
		$vc       = $vc * (1.0 - $alpha2) + $residual;
	    }

            # Hold OCXO control voltage for 15 minutes
            $hold     = 1;
            $wait     = $max_hold_time;

	    if ($mode == 1) {
		# Set time constant to fast mode
		$alpha1   = 0.3;
		$gain1    = 10.0;
		$alpha2   = 1.0;
		$gain2    = 0.007;
		$gain3    = 1.0;
		$mode     = 0;
	    }
        }

        if (! $hold) {
            # Gain
            $error    = $error * ( 1.0 - $alpha1) + $pfd * $gain1 * $alpha1;

            # Filter
            $vc       = $vc * (1.0 - $alpha2) + $error * $alpha2 + $residual;
            $residual += $error * $gain2;

        }

        $val      = int($vc * $gain3 + 32768);

        # Clip/clamp to 16 bits
        if ($val > 65535) {
            $val = 65535;
            $vc  = 32767.0 / $gain3;
        } elsif ($val < 0) {
            $val = 0;
            $vc  = -32768.0 / $gain3;
        }

        poke($vc_reg, $val);

        ($temp, $tint, $iocxo, $tocxo, $tcpu, $tedge) = sensors;

        printf("%f %.4f  %fA %.4f  %f %f  % .0f % .0f  % f  %f %f  0x%04x  %d %d %d %d\n",
               $temp, $tint,
               $iocxo, $tocxo,
               $tcpu, $tedge,
               $pfd, $fd,
               $error,
               $residual, $vc,
               $val,
               $status, $lock_cnt, $mode, $hold);

        if (! $status && $pfd == 0) {
            $lock_cnt++;
        } else {
            $lock_cnt = 0;
        }
        if (! $status && $fd == 0) {
            $flock_cnt++;
        } else {
            $flock_cnt = 0;
        }

        # Switch time constants when we are in lock
        if (! $hold && $lock_cnt > 20) {
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

        # Turn off hold after wait timer runs out
        if ($hold) {
            $wait--;
            if (($wait <= 0) ||
                # See if we can exit hold early if frequency is locked
                (! $status && $flock_cnt >= 3 && $wait <= ($max_hold_time - $min_hold_time))) {
                $hold = 0;
            }
        }

        # Compare display time to local time for daylight savings or leap second
        display_rtc;

        # Wait +200mS after the second for the phase detector
        ($tmp, $microseconds) = Time::HiRes::gettimeofday;
        Time::HiRes::usleep(1000000 - $microseconds + 200000) if (!$g_sim);
    }
}



sub coeff
{
    my ($c, $r1, $r2, $T)= @_;

    my $t1       = $c * $r1;
    my $t2       = $c * $r2;

    my $y1       = 1.0;
    my $x0       = ($T + 2.0 * $t2) / (2.0 * ($t1 + $t2));
    my $x1       = ($T - 2.0 * $t2) / (2.0 * ($t1 + $t2));

    my $w        = sqrt($g_Kd * $g_K0 / ($t1 + $t2));
    my $z        = $t2 * $w / 2.0;

    printf ("# t1 = %f,  t2 = %f\n", $t1, $t2);
    printf ("# w = %f,  z = %f\n", $w, $z);
    printf ("# y[n] = %f * y[n-1] + %f * x[n-1] + %f * x[n]\n", $y1, $x1, $x0);

    return ($y1, $x1, $x0);

}

sub plag
{
    my $mode     = 0;
    my $hold     = 0;
    my $wait     = 0;

    my $temp;
    my $tcpu;
    my $tedge;
    my $tint;
    my $iocxo;
    my $tocxo;

    my @x        = (0.0, 0.0);
    my @y        = (-7317.0, 0.0);

    my $T        = 1.0;
    my @c        = (1.0, 1.0);
    my @r1       = (120.0, 1200.0);
# 0.707 damping
#   my @r2       = (1032.02, 1612.52);
# 0.707, 0.9 damping
    my @r2       = (1032.02, 2284.45);

    my $y1;
    my $x0;
    my $x1;

    my $pfd;
    my $pfd_last;
    my $fd;
    my $val;
    my $microseconds;
    my $tmp;
    my $i;
    my $status;
    my $lock_cnt  = 0;
    my $flock_cnt = 0;


    ($y1, $x1, $x0) = coeff($c[0], $r1[0], $r2[0], $T);

    # Initialize the PFD and its control voltage
    init_pfd(int($y[0] + 32768));

    while (1) {

        $pfd_last = $pfd;

        # Read Phase Frequency Detector
	($pfd, $fd, $status) = read_pfd;

        # Detect a large jump in phase when in slow response mode or
        # dropped pps from GPS
        if (($mode == 1 && abs($pfd - $pfd_last) > 10) || $status) {
            # Hold OCXO control voltage for 15 minutes
            $hold     = 1;
            $wait     = $max_hold_time;

	    if ($mode == 1) {
		# Set time constant to fast mode
		($y1, $x1, $x0) = coeff($c[0], $r1[0], $r2[0], $T);
		$mode     = 0;
	    }
        }

        if (! $hold) {
            $y[1]    = $y[0];
            $x[1]    = $x[0];
            $x[0]    = $pfd;

            $y[0]    = $y1 * $y[1] + $x0 * $x[0] + $x1 * $x[1];
        }

        $val      = int($y[0] + 32768);

        # Clip/clamp to 16 bits
        if ($val > 65535) {
            $val = 65535;
        } elsif ($val < 0) {
            $val = 0;
        }

        poke($vc_reg, $val);

        ($temp, $tint, $iocxo, $tocxo, $tcpu, $tedge) = sensors;

        printf("%f %.4f  %fA %.4f  %f %f  % .0f % .0f  -  %f %d  0x%04x  %d %d %d %d\n",
               $temp, $tint,
               $iocxo, $tocxo,
               $tcpu, $tedge,
               $pfd, $fd,
               $y[0], int($y[0]),
               $val,
               $status, $lock_cnt, $mode, $hold);

        if (! $status && $pfd == 0) {
            $lock_cnt++;
        } else {
            $lock_cnt = 0;
        }
        if (! $status && $fd == 0) {
            $flock_cnt++;
        } else {
            $flock_cnt = 0;
        }

        # Switch time constants when we are in lock
        if (! $hold) {
	    if ($mode == 0 && $lock_cnt > 20) {
		($y1, $x1, $x0) = coeff($c[1], $r1[1], $r2[1], $T);
		$mode     = 1;
	    } elsif ($mode == 1 && abs($pfd) > 10) {
		($y1, $x1, $x0) = coeff($c[0], $r1[0], $r2[0], $T);
		$mode     = 0;
	    }
	}

        # Turn off hold after wait timer runs out
        if ($hold) {
            $wait--;
            if (($wait <= 0) ||
                # See if we can exit hold early if frequency is locked
                (! $status && $flock_cnt >= 3 && $wait <= ($max_hold_time - $min_hold_time))) {
                $hold = 0;
            }
        }

        # Compare display time to local time for daylight savings or leap second
        display_rtc;

        # Wait +200mS after the second for the phase detector
        ($tmp, $microseconds) = Time::HiRes::gettimeofday;
        Time::HiRes::usleep(1000000 - $microseconds + 200000) if (!$g_sim);
    }
}



getopts('a:his');
$g_algo = $Getopt::Std::opt_a if ($Getopt::Std::opt_a);
$g_init = 1 if ($Getopt::Std::opt_i);
$g_sim  = 1 if ($Getopt::Std::opt_s);
usage("")   if $Getopt::Std::opt_h;


init_sensors;
init_pll;

# Display the time from the RTC while waiting for GPS
set_time(time);

wait_for_gps;

if ($g_algo == 0) {
    loworder;
} elsif ($g_algo == 1) {
    plag;
}
