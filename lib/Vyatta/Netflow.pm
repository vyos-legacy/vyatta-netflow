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
);
use base qw(Exporter);
use File::Basename;
use File::Compare;
use POSIX;

use Vyatta::Config;

my $acct_debug = 1;
my $acct_log   = '/tmp/acct';

my $daemon = '/usr/sbin/pmacctd';

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
    my ($intf, $conf_file) = @_;

    print "Starting [$intf] flow-accounting\n";
    my $cmd  = "$daemon -f $conf_file";
    system($cmd);
    acct_log("start_daemon [$intf]");
}

sub stop_daemon {
    my ($intf) = @_;

    my $pid_file = acct_get_pid_file($intf);
    my $pid      = is_running($pid_file);
    if ($pid != 0) {
	print "Stopping [$intf] flow-accounting\n";
	system("kill -INT $pid");
	acct_log("stop_daemon [$intf]");
    } else {
	acct_log("stop daemon called while not running [$intf]");
    }
}

sub restart_daemon {
    my ($intf, $conf_file) = @_;

    my $pid_file = acct_get_pid_file($intf);
    my $pid      = is_running($pid_file);
    if ($pid != 0) {
	system("kill -INT $pid");
	print "Stopping [$intf] flow-accounting\n";
	acct_log("restart_deamon [$intf]");
	sleep 5; # give the daemon a chance to properly shutdown
    } 
    start_daemon($intf, $conf_file);	
}

sub acct_get_pid_file {
    my ($intf) = @_;

    return "/var/run/pmacctd-$intf.pid";
}

sub acct_get_pipe_file {
    my ($intf) = @_;

    return "/tmp/pmacctd-$intf.pipe";
}

sub acct_get_conf_file {
    my ($intf) = @_;

    return "/etc/pmacct/pmacctd-$intf.conf";
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
    my @intfs = $config->listOrigNodes();
    return @intfs;
}

1;
