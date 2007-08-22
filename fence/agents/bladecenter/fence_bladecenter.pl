#!/usr/bin/perl

###############################################################################
###############################################################################
##
##  Copyright (C) Sistina Software, Inc.  1997-2003  All rights reserved.
##  Copyright (C) 2004-2007 Red Hat, Inc.  All rights reserved.
##  
##  This copyrighted material is made available to anyone wishing to use,
##  modify, copy, or redistribute it subject to the terms and conditions
##  of the GNU General Public License v.2.
##
###############################################################################
###############################################################################
#
# Tested against:
# Firmware Type     Build ID   File Name     Released  Revision
# ----------------  --------   ------------  --------  --------
# Main application  BRET67D    CNETMNUS.PKT  07-22-04  16
# Boot ROM          BRBR67D    CNETBRUS.PKT  07-22-04  16  	
# Remote control    BRRG67D    CNETRGUS.PKT  07-22-04  16   	
#
use Getopt::Std;
use Net::Telnet ();

# Get the program name from $0 and strip directory names
$_=$0;
s/.*\///;
my $pname = $_;

$action = "reboot"; # Default fence action

# WARNING!! Do not add code bewteen "#BEGIN_VERSION_GENERATION" and 
# "#END_VERSION_GENERATION"  It is generated by the Makefile

#BEGIN_VERSION_GENERATION
$RELEASE_VERSION="";
$REDHAT_COPYRIGHT="";
$BUILD_DATE="";
#END_VERSION_GENERATION


sub usage
{
	print "Usage:\n";
	print "\n";
	print "$pname [options]\n";
	print "\n";
	print "Options:\n";
	print "  -a <ip>          IP address or hostname of blade center\n";
	print "  -h               usage\n";
	print "  -l <name>        Login name\n";
	print "  -n <num>         blade number to operate on\n";
	print "  -o <string>      Action:  on, off, reboot (default) or status\n";
	print "  -p <string>      Password for login\n";
	print "  -S <path>        Script to run to retrieve password\n";
	print "  -q               quiet mode\n";
	print "  -V               version\n";

	exit 0;
}

sub fail
{
	($msg) = @_;
	print $msg."\n" unless defined $quiet;
	$t->close if defined $t;
	exit 1;
}

sub fail_usage
{
	($msg)=@_;
	print STDERR $msg."\n" if $msg;
	print STDERR "Please use '-h' for usage.\n";
	exit 1;
}

sub version
{
	print "$pname $RELEASE_VERSION $BUILD_DATE\n";
	print "$REDHAT_COPYRIGHT\n" if ( $REDHAT_COPYRIGHT );

	exit 0;
}

sub get_options_stdin
{
	my $opt;
	my $line = 0;
	while( defined($in = <>) )
	{
		$_ = $in;
		chomp;

		# strip leading and trailing whitespace
		s/^\s*//;
		s/\s*$//;
	
		# skip comments
		next if /^#/;

		$line+=1;
		$opt=$_;
		next unless $opt;

		($name,$val)=split /\s*=\s*/, $opt;

		if ( $name eq "" )
		{  
			print STDERR "parse error: illegal name in option $line\n";
			exit 2;
		}
	
		# DO NOTHING -- this field is used by fenced
		elsif ($name eq "agent" ) { } 

		elsif ($name eq "ipaddr" ) 
		{
			$host = $val;
		} 
		elsif ($name eq "login" ) 
		{
			$login = $val;
		} 
		elsif ($name eq "option" )
		{
			$action = $val;
		}
		elsif ($name eq "passwd" ) 
		{
			$passwd = $val;
		}
		elsif ($name eq "passwd_script" ) {
			$passwd_script = $val;
		}
		elsif ($name eq "blade" ) 
		{
			$bladenum = $val;
		} 
		elsif ($name eq "debuglog" ) 
		{
			$verbose = $val;
		} 
	}
}

sub get_power_state
{
	my ($junk) = @_;
	fail "illegal argument to get_power_state()" if defined $junk;

	my $state="";

	$t->print("env -T system:blade[$bladenum]");
	($text, $match) = $t->waitfor("/system:blade\\[$bladenum\\]>/");

	$t->print("power -state");
	($text, $match) = $t->waitfor("/system:blade\\[$bladenum\\]>/");

	if ($text =~ /power -state\n(on|off)/im )
	{
		$state = $1;
	}
	else
	{
		fail "unexpected powerstate";
	}

	$t->print("env -T system");
	($text, $match) = $t->waitfor("/system>/");

	$_=$state;
}

sub set_power_state
{
	my ($set,$junk) = @_;
	fail "missing argument to set_power_state()" unless defined $set;
	fail "illegal argument to set_power_state()" if defined $junk;

	my $state="";

	$t->print("env -T system:blade[$bladenum]");
	($text, $match) = $t->waitfor("/system:blade\\[$bladenum\\]>/");

	$t->print("power -$set");
	($text, $match) = $t->waitfor("/system:blade\\[$bladenum\\]>/");

	fail "unexpected powerstate" unless ($text =~ /power -$set\nOK/im );

	$t->print("env -T system");
	($text, $match) = $t->waitfor("/system>/");

	# need to sleep a few seconds to make sure that the bladecenter 
	# has time to issue the power on/off command
	sleep 5;

	$_=$state;
}

# MAIN

if (@ARGV > 0) 
{
	getopts("a:hl:n:o:p:S:qv:V") || fail_usage ;

	usage if defined $opt_h;
	version if defined $opt_V;

	$host     = $opt_a if defined $opt_a;
	$login    = $opt_l if defined $opt_l;
	$passwd   = $opt_p if defined $opt_p;
	$action   = $opt_o if defined $opt_o;
	$bladenum = $opt_n if defined $opt_n;
	$verbose  = $opt_v if defined $opt_v;
	$quiet    = $opt_q if defined $opt_q;

	if (defined $opt_S) {
		$pwd_script_output = `$opt_S`;
		chomp($pwd_script_output);
		if ($pwd_script_output) {
			$passwd = $pwd_script_output;
		}
	}

	fail_usage "Unknown parameter." if (@ARGV > 0);

	fail_usage "No '-a' flag specified." unless defined $host;
	fail_usage "No '-n' flag specified." unless defined $bladenum;
	fail_usage "No '-l' flag specified." unless defined $login;
	fail_usage "No '-p' or '-S' flag specified." unless defined $passwd;
	fail_usage "Unrecognised action '$action' for '-o' flag"
		unless $action =~ /^(on|off|reboot|status)$/i;
} 
else 
{
	get_options_stdin();

	fail "failed: no IP address" unless defined $host;
	fail "failed: no blade number" unless defined $bladenum;
	fail "failed: no login name" unless defined $login;
	fail "failed: unrecognised action: $action"
		unless $action =~ /^(on|off|reboot|status)$/i;

	if (defined $passwd_script) {
		$pwd_script_output = `$passwd_script`;
		chomp($pwd_script_output);
		if ($pwd_script_output) {
			$passwd = $pwd_script_output;
		}
	}
	fail "failed: no password" unless defined $passwd;
}

# convert $action to lower case 
$_=$action;
if    (/^on$/i)     { $action = "on"; }
elsif (/^off$/i)    { $action = "off"; }
elsif (/^reboot$/i) { $action = "reboot"; }
elsif (/^status$/i) { $action = "status"; }

#
# Set up and log in
#
$t = new Net::Telnet;

$t->input_log($verbose) if $verbose;
$t->open($host);

$t->waitfor('/username:/');
$t->print($login);

$t->waitfor('/password:/');
$t->print($passwd);

($text, $match) = $t->waitfor("/system>/");

#
# Do the command
#
$success=0;
$_ = $action;
if (/(on|off)/)
{
	set_power_state $action;
	get_power_state;
	$success = 1 if (/^$action$/i);
}
elsif (/reboot/)
{
	set_power_state off;
	get_power_state;
	
	if (/^off$/i)
	{
		set_power_state on;
		get_power_state;
		$success = 1 if (/^on$/i);
	}
}
elsif (/status/)
{
	get_power_state;
	$state=$_;
	$success = 1 if defined $state;
}
else
{
	fail "fail: illegal action";
}

$t->print("exit");
sleep 1;
$t->close();


if ($success)
{
	print "success: blade$bladenum $action". ((defined $state) ? ": $state":"")
		."\n" unless defined $quiet;
	exit 0;
}
else
{
	fail "fail: blade$bladenum $action";	
	exit 1
}
