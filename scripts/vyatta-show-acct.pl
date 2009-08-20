#!/usr/bin/perl
#
# Module: vyatta-show-acct.pl
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
# Portions created by Vyatta are Copyright (C) 2008 Vyatta, Inc.
# All Rights Reserved.
# 
# Author: Stig Thormodsrud
# Date: June 2009
# Description: pmacct show commands.
# 
# **** End License ****
#

use Getopt::Long;
use POSIX;

use lib "/opt/vyatta/share/perl5";
use Vyatta::Netflow;

use warnings;
use strict;


sub validate_intf {
    my ($intf) = @_;

    my $pid_file = acct_get_pid_file($intf);
    if (!is_running($pid_file)) {
	print "accounting is not running on [$intf]\n";
	exit 1;
    }
}

sub display_lines {
    my (@lines) = @_;

    #format output for 80 column display
    my $format = "%-15s %-15s %-5s %-5s %5s %10s %10s %7s\n";
    printf($format, 
	   'Src Addr', 'Dst Addr', 'Sport', 'Dport', 'Proto', 
	   'Packets','Bytes', 'Flows');
    my $count = 0;
    my ($tot_flows, $tot_pkts, $tot_bytes) = (0, 0, 0);
    foreach my $line (@lines) {
	my ($src, $dst, $sport, $dport, $proto, $tos, $pkts, $flows, $bytes) =
	    split(/\s+/, $line);	
	next if !defined $src or $src !~ m/\d+\.\d+\.\d+\.\d+/;
	printf($format, 
	       $src, $dst, $sport, $dport, $proto, $pkts, $bytes, $flows);
	$count++;
	$tot_flows += $flows;
	$tot_pkts  += $pkts;
	$tot_bytes += $bytes;
    }
    print "\nTotal entries: $count\n";
    print "Total flows  : $tot_flows\n";
    print "Total pkts   : $tot_pkts\n";
    print "Total bytes  : $tot_bytes\n";
}

sub show_acct {
    my ($intf) = @_;

    print "Accounting flows for [$intf]\n";
    my $pipe_file = acct_get_pipe_file($intf);
    my @lines = `/usr/bin/pmacct -p $pipe_file -s -T bytes`;
    display_lines(@lines);
}

sub show_acct_host {
    my ($intf, $host) = @_;

    my $pipe_file = acct_get_pipe_file($intf);
    my @slines = `/usr/bin/pmacct -p $pipe_file -c src_host -M $host -T bytes`;
    my @dlines = `/usr/bin/pmacct -p $pipe_file -c dst_host -M $host -T bytes`;
    display_lines(@slines,@dlines);
}

sub show_acct_port {
    my ($intf, $port) = @_;

    my $pipe_file = acct_get_pipe_file($intf);
    my @slines = `/usr/bin/pmacct -p $pipe_file -c src_port -M $port -T bytes`;
    my @dlines = `/usr/bin/pmacct -p $pipe_file -c dst_port -M $port -T bytes`;
    display_lines(@slines,@dlines);
}

sub clear_acct {
    my ($intf) = @_;

    print "clearings accounting for [$intf]\n";
    my $pipe_file = acct_get_pipe_file($intf);
    system("/usr/bin/pmacct -p $pipe_file -e");
}

#
# main
#
my ($action, $intf, $host, $port);

GetOptions("action=s"     => \$action,
           "intf=s"       => \$intf,
	   "host=s"       => \$host,
           "port=s"       => \$port);

if (! defined $action) {
    die "no action\n";
}

if ($action eq 'show') {
    if ($intf) {
	validate_intf($intf);
	show_acct($intf);
    } else {
	my @intfs = acct_get_intfs();
	if (scalar(@intfs) > 0) {
	    foreach my $intf (@intfs) {
		validate_intf($intf);
		show_acct($intf);
		print "\n";
	    }
	} else {
	    print "Accounting not configured on any interface\n";
	    exit 1;
	}
    }
    exit 0;
}

if ($action eq 'show-host') {
    die "no host" if ! defined $host;
    if ($intf) {
	validate_intf($intf);
	show_acct_host($intf, $host);
    } 
    exit 0;
}

if ($action eq 'show-port') {
    die "no port" if ! defined $port;
    if ($intf) {
	validate_intf($intf);
	show_acct_port($intf, $port);
	exit 0;
    }
}

if ($action eq 'clear') {
    if ($intf) {
	validate_intf($intf);
	clear_acct($intf);
    } else {
	my @intfs = acct_get_intfs();
	foreach my $intf (@intfs) {
	    validate_intf($intf);
	    clear_acct($intf);
	}
    }
    exit 0;
}

exit 1;

# end of file
