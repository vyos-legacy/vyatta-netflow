#
# Module: Vyatta::Netflow.pm
# 
# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2008-2009 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: June 2009
# Description: Common netflow definitions/funcitions
# 
# **** End License ****
#
package Vyatta::Netflow;
use strict;
use warnings;

our @EXPORT = qw(
    start_daemon
    restart_daemon
    stop_daemon
    is_running
    acct_log
    acct_get_pid_file
    acct_get_pipe_file
    acct_get_conf_file
    acct_get_intfs
    acct_read_file
    acct_write_file
    acct_get_ifindx
);
use base qw(Exporter);
use File::Basename;
use File::Compare;
use POSIX;

use Vyatta::Config;

my $acct_debug = 1;
my $acct_log   = '/tmp/acct';

my $daemon = '/usr/sbin/uacctd';

sub acct_log {
    return if ! $acct_debug;
    my $timestamp = strftime("%Y%m%d-%H:%M.%S", localtime);
    open my $fh, '>>', $acct_log
	or die "Can't open $acct_log: $!";
    print $fh "$timestamp: ", @_ , "\n";
    close $fh;
}

sub is_running {
    my ($pid_file) = @_;

    if (-f $pid_file) {
	my $pid = `cat $pid_file`;
	$pid =~ s/\s+$//;  # chomp doesn't remove nl
	my $ps = `ps -p $pid -o comm=`;
	if (defined($ps) && $ps ne "") {
	    return $pid;
	} 
    }
    return 0;
}

sub start_daemon {
    my ($conf_file) = @_;

    print "Starting flow-accounting\n";
    my $cmd  = "$daemon -f $conf_file";
    system($cmd);
    acct_log("start_daemon");
}

sub stop_daemon {

    my $pid_file = acct_get_pid_file();
    my $pid      = is_running($pid_file);
    if ($pid != 0) {
	print "Stopping flow-accounting\n";
	system("kill -INT $pid");
	acct_log("stop_daemon");
    } else {
	acct_log("stop daemon called while not running");
    }
}

sub restart_daemon {
    my ($conf_file) = @_;

    my $pid_file = acct_get_pid_file();
    my $pid      = is_running($pid_file);
    if ($pid != 0) {
	system("kill -INT $pid");
	print "Stopping flow-accounting\n";
	acct_log("restart_deamon");
	sleep 5; # give the daemon a chance to properly shutdown
    } 
    start_daemon($conf_file);	
}

sub acct_get_pid_file {
    return "/var/run/uacctd.pid";
}

sub acct_get_pipe_file {
    return "/tmp/uacctd.pipe";
}

sub acct_get_conf_file {
    return "/etc/pmacct/uacctd.conf";
}

sub acct_read_file {
    my ($file) = @_;
    my @lines;
    if ( -e $file) {
	open(my $FILE, '<', $file) or die "Error: read $!";
	@lines = <$FILE>;
	close($FILE);
	chomp @lines;
    }
    return @lines;
}

sub is_same_as_file {
    my ($file, $value) = @_;

    return if ! -e $file;

    my $mem_file = '';
    open my $MF, '+<', \$mem_file or die "couldn't open memfile $!\n";
    print $MF $value;
    seek($MF, 0, 0);
    
    my $rc = compare($file, $MF);
    return 1 if $rc == 0;
    return;
}

sub acct_write_file {
    my ($file, $config) = @_;

    # Avoid unnecessary writes.  At boot the file will be the
    # regenerated with the same content.
    return if is_same_as_file($file, $config);

    open(my $fh, '>', $file) || die "Couldn't open $file - $!";
    print $fh $config;
    close $fh;
    return 1;
}

sub acct_get_intfs {
    my $config = new Vyatta::Config;
    my $path   = "system flow-accounting interface";
    $config->setLevel($path);
    my @intfs = $config->returnOrigValues();
    return @intfs;
}

sub acct_get_ifindx {
    my ($intf) = @_;

    return if ! defined $intf;
    my $cmd  = "ip link show dev $intf 2> /dev/null ";
       $cmd .= "| egrep '^[0-9]' | cut -d ':' -f 1";
    my $ifindx = `$cmd`;
    if ($? > 0 ) {
        print "Invalid interface [$intf]\n";
        return;
    }
    chomp  $ifindx;
    return $ifindx;
}

1;
