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

my $pmacct = '/usr/bin/pmacct';

sub validate_intf {
    my ($intf) = @_;

    my $pid_file = acct_get_pid_file($intf);
    if (!is_running($pid_file)) {
	print "flow-accounting is not running on [$intf]\n";
	exit 1;
    }
}

# taken from "perldoc -q commas"
sub commify {
    local($_) = shift;
    1 while s/^(-?\d+)(\d{3})/$1,$2/;
    return $_;
} 

sub display_lines {
    my ($topN, @lines) = @_;

    $topN = 0xffffffff if ! defined $topN;

    #format output for 80 column display
    my $format = "%-15s %-15s %-5s %-5s %5s %10s %10s %7s\n";
    if ($topN != 0) {
	printf($format, 
	       'Src Addr', 'Dst Addr', 'Sport', 'Dport', 'Proto', 
	       'Packets','Bytes', 'Flows');
    }
    my $count = 0;
    my ($tot_flows, $tot_pkts, $tot_bytes) = (0, 0, 0);
    foreach my $line (@lines) {
        my ($id, $class, $src_mac, $dst_mac, $vlan, $src_as, $dst_as,
            $src_ip, $dst_ip, $sport, $dport, $tcp_flags, $proto, 
            $tos, $pkts, $flows, $bytes) = split(/\s+/, $line);
	next if !defined $src_ip or $src_ip !~ m/\d+\.\d+\.\d+\.\d+/;
	$count++;
	$tot_flows += $flows;
	$tot_pkts  += $pkts;
	$tot_bytes += $bytes;
	if ($topN != 0) {
	    printf($format, 
		   $src_ip, $dst_ip, $sport, $dport, $proto, 
                   $pkts, $bytes, $flows);
	}
	last if $topN != 0 and $count >= $topN;
    }
    print "\nTotal entries: ", commify($count), "\n";
    print "Total flows  : ", commify($tot_flows), "\n";
    print "Total pkts   : ", commify($tot_pkts), "\n";
    print "Total bytes  : ", commify($tot_bytes), "\n";
}

sub show_acct {
    my ($intf, $topN) = @_;

    print "flow-accounting for [$intf]\n";
    my $pipe_file = acct_get_pipe_file($intf);
    my @lines = `$pmacct -a -p $pipe_file -s -T bytes`;
    display_lines($topN, @lines);
}

sub show_acct_host {
    my ($intf, $host) = @_;

    my $pipe_file = acct_get_pipe_file($intf);
    my @slines = `$pmacct -a -p $pipe_file -c src_host -M $host -T bytes`;
    my @dlines = `$pmacct -a -p $pipe_file -c dst_host -M $host -T bytes`;
    display_lines(undef, @slines,@dlines);
}

sub show_acct_port {
    my ($intf, $port) = @_;

    my $pipe_file = acct_get_pipe_file($intf);
    my @slines = `$pmacct -a -p $pipe_file -c src_port -M $port -T bytes`;
    my @dlines = `$pmacct -a -p $pipe_file -c dst_port -M $port -T bytes`;
    display_lines(undef, @slines,@dlines);
}

sub clear_acct {
    my ($intf) = @_;

    print "clearings flow-accounting for [$intf]\n";
    my $pipe_file = acct_get_pipe_file($intf);
    system("$pmacct -p $pipe_file -e");
}

sub alphanum_split {
    my ($str) = @_;
    my @list = split m/(?=(?<=\D)\d|(?<=\d)\D)/, $str;
    return @list;
}

sub natural_order {
    my ($a, $b) = @_;
    my @a = alphanum_split($a);
    my @b = alphanum_split($b);
  
    while (@a && @b) {
	my $a_seg = shift @a;
	my $b_seg = shift @b;
	my $val;
	if (($a_seg =~ /\d/) && ($b_seg =~ /\d/)) {
	    $val = $a_seg <=> $b_seg;
	} else {
	    $val = $a_seg cmp $b_seg;
	}
	if ($val != 0) {
	    return $val;
	}
    }
    return @a <=> @b;
}

sub intf_sort {
    my @a = @_;
    my @new_a = sort { natural_order($a,$b) } @a;
    return @new_a;
}


#
# main
#
my ($action, $intf, $host, $port, $topN);

GetOptions("action=s"     => \$action,
           "intf=s"       => \$intf,
	   "host=s"       => \$host,
           "port=s"       => \$port,
           "topN=s"       => \$topN,
);

if (! defined $action) {
    die "no action\n";
}

if ($action eq 'show') {
    if ($intf) {
	validate_intf($intf);
	show_acct($intf, $topN);
    } else {
	my @intfs = acct_get_intfs();
	@intfs = intf_sort(@intfs);
	if (scalar(@intfs) > 0) {
	    foreach my $intf (@intfs) {
		validate_intf($intf);
		show_acct($intf);
		print "\n";
	    }
	} else {
	    print "flow-accounting not configured on any interface\n";
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

if ($action eq 'restart') {
    my $conf_file = acct_get_conf_file($intf);
    if (-e $conf_file) {
	restart_daemon($intf, $conf_file);
	exit 0;
    } else {
	print "flow-accounting not configured on [$intf]\n";
	exit 1;
    }
}

exit 1;

# end of file
