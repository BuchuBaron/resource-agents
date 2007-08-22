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

# This fencing agent is written for the Baytech RPC27-20nc in conjunction with
# a Cyclades terminal server.  The Cyclades TS exports the RPC's serial port
# via a Telnet interface.  Other interfaces, such as SSH, are possible.  
# However, this script relys upon the assumption that Telnet is used.  Future
# features to this agent would allow the agent to work with a mulitude of 
# different communication protocols such as Telnet, SSH or Kermit.
#
# The other assumption that is made is that Outlet names do not end in space.
# The name "Foo" and "Foo    " are identical when the RPC prints them with
# the status command.

use Net::Telnet;
use Getopt::Std;

# WARNING!! Do not add code bewteen "#BEGIN_VERSION_GENERATION" and 
# "#END_VERSION_GENERATION"  It is generated by the Makefile

#BEGIN_VERSION_GENERATION
$RELEASE_VERSION="";
$REDHAT_COPYRIGHT="";
$BUILD_DATE="";
#END_VERSION_GENERATION

# Get the program name from $0 and strip directory names
$_=$0;
s/.*\///;
my $pname = $_;


sub rpc_error 
{
	if (defined $error_message && $error_message ne "")
	{
		chomp $error_message;
		die "$error_message\n";
	}
	else
	{
		die "read timed-out\n"
	}
}

sub usage 
{

    print "Usage:\n";
    print "\n";
    print "$pname [options]\n";
    print "\n";
    print "Options:\n";
    print " -a host        host to connect to\n";
    print " -D             debugging output\n";
    print " -h             usage\n";
    print " -l string      user name\n";
    print " -o string      action: On,Off,Status or Reboot (default)\n";
    print " -n string      outlet name\n";
    print " -p string      password\n";
    print " -S path        script to run to retrieve password\n";
    print " -V             version\n";

    exit 0;
}

sub fail
{
  ($msg)=@_;
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

# Get operating paramters, either with getopts or from STDIN
sub get_options
{
   $action = "Reboot";
   if (@ARGV > 0) {
      getopts("n:l:p:S:o:a:VhD") || fail_usage ;

      usage if defined $opt_h;
      version if defined $opt_V;

      fail_usage "Unkown parameter." if (@ARGV > 0);

   } else {
      get_options_stdin();
   } 

   fail "failed: must specify hostname" unless defined $opt_a;
   $host=$opt_a;
   $port=23 unless ($opt_a =~ /:/);

   $action = $opt_o if defined $opt_o;
   fail "failed: unrecognised action: $action"
         unless $action=~ /^(Off|On|Reboot|status)$/i;
   
   fail "failed: no outletname" unless defined $opt_n;
   $outlet = $opt_n;

   $debug=$opt_D if defined $opt_D;
   $quiet=$opt_q if defined $opt_q;
   $user=$opt_l if defined $opt_l;
   $passwd=$opt_p if defined $opt_p;
   if (defined $opt_S) {
     $pwd_script_out = `$opt_S`;
     chomp($pwd_script_out);
     if ($pwd_script_out) {
       $passwd=$pwd_script_out;
     }
   }

   if(defined $passwd && !defined $user)
   {
      fail "failed: password given without username";
   }
}

# Get options from STDIN
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

	elsif ($name eq "host" ) 
	{
	    $opt_a = $val;
	} 

	elsif ($name eq "login" ) 
	{
	    $opt_l = $val;
	} 

	elsif ($name eq "passwd" ) 
	{
	    $opt_p = $val;
	} 

    elsif ($name eq "passwd_script") {
        $opt_S = $val;
    }

	elsif ($name eq "action" ) 
	{
	    $opt_o = $val;
	} 

	elsif ($name eq "outlet" ) 
	{
	    $opt_n = $val;
	} 

    }
}

# Get a bunch of lines.  The newlines must terminate complete lines.
sub getlines
{
	my $data=$t->get();
	return undef unless defined $data;
	my @chars = split //,$data;
	my @lines;
	my $line="";

	for (my $i=0;$i<@chars;$i++)
	{
		$line = $line.$chars[$i];
		next unless $chars[$i] eq "\n";
		$lines[@lines] = $line;
		$line = "";
	}
	$lines[@lines] = $line unless $line eq "";

	return @lines;
}

# Fill the global input buffer of lines read.  All lines are terminated with
# a newline.  If a line is not terminated, the next call to fill buffer will
# append the last line of the input buffer with the first line that it gets from
# getlines()
sub fill_buffer
{
	my @lines = getlines();
	return undef unless @lines;

	if(@buffer)
	{
		if ( $buffer[$#buffer]=~/\n/) { }
		else
		{
			$buffer[$#buffer] = $buffer[$#buffer].$lines[0];
			shift @lines;
		}
	}

	foreach (@lines) 
	{ 
		push @buffer,$_;
	}
}



#
# ($p_index,@data) = get_match @patterns;
#
# searches the input buffers for the patterns specified by the regeps in 
# @patterns, when a match is found, all the lines through the matched 
# pattern line are removed from the global input buffer and returned in the
# array @data.  The index into @patterns for the matching pattern is also
# returned.
sub get_match
{
	my (@patterns) = @_;
	$b_index = 0 unless defined $b_index;

	fill_buffer() unless defined @buffer;

	for(;;)
	{
		for(my $bi=$b_index; $bi<@buffer; $bi++)
		{
			for(my $pat=0; $pat<@patterns; $pat++)
			{
				if($buffer[$bi] =~ /$patterns[$pat]/)
				{
					$b_index = 0;
					my @rtrn = splice(@buffer,0,$bi);
					shift @buffer;
				
					if($debug)
					{
						foreach (@rtrn) { print $_ }
						print "$patterns[$pat] ";
					}
					
					return ($pat,@rtrn);
				}
			}
			$b_index = $bi;
		}

		fill_buffer();
	}
}

#
# ($bt_num,$bt_name,$bt_state,$bt_locked) = parse_status $outlet,@data;
#
# This parses the data @data and searches for an outlet named $outlet.
# The data will be in the form:
# 
#   Average Power:    0 Watts        Apparent Power:   17 VA
# 
#   True RMS Voltage: 120.0 Volts
# 
#   True RMS Current:   0.1 Amps     Maximum Detected:   0.2 Amps     
# 
#   Internal Temperature:  19.5 C
# 
#   Outlet Circuit Breaker: Good
# 
#    1)...Outlet  1       : Off           2)...Outlet  2       : Off          
#    3)...Outlet  3       : On            4)...Outlet  4       : On           
#    5)...Outlet  5       : On            6)...Outlet  6       : On           
#    7)...Outlet  7       : On            8)...Outlet  8       : On           
#    9)...Outlet  9       : On           10)...Outlet 10       : On           
#   11)...Outlet 11       : On           12)...Outlet 12       : On           
#   13)...Outlet 13       : On           14)...Outlet 14       : On           
#   15)...Outlet 15       : On           16)...Outlet 16       : On           
#   17)...Outlet 17       : On           18)...Outlet 18       : On           
#   19)...Outlet 19       : On           20)...Outlet 20       : On    Locked 
#
sub parse_status
{
	my $outlet = shift;
	my @data = @_;

	my $bt_num="";
	my $bt_name="";
	my $bt_state="";
	my $bt_locked="";

	# Verify that the Outlet name exists
	foreach my $line (@data)
	{
		next unless $line =~ /^[ 12][0-9]\)\.\.\./;

		my @entries = split /([ 12][0-9])\)\.\.\./,$line;
	
		foreach my $entry (@entries)
		{
			next if $entry eq "";
			
			if($entry =~ /^([ 12][0-9])$/)
			{
				$bt_num = $1;
			}
			elsif($entry =~ /^(.{15}) : (On|Off)(.*)/)
			{
	
				$bt_name = $1;
				$bt_state = $2;
				$bt_locked = $3;
	
				$_ = $bt_name;
				s/\s*$//;
				$bt_name = $_;
	
				$_ = $bt_locked;
				s/\s*$//;
				$bt_locked = $_;
	
				last if ($bt_name eq $outlet);
	
				$bt_name = "";
				next;
			}
			else
			{
				die "parse error: $entry";
			}
		}
		last if ($bt_name ne "");
	}
	
	if ($bt_name eq "")
	{
		$bt_num=undef;
		$bt_name=undef;
		$bt_state=undef;
		$bt_locked=undef;
	}

	return ($bt_num,$bt_name,$bt_state,$bt_locked);
}

##########################################################################
#
# Main

get_options;


if (defined $port)
{
	$t = new Net::Telnet(Host=>$host, Port=>$port) or 
		die "Unable to connect to $host:$port: ".($!?$!:$_)."\n";
}
else
{
	$t = new Net::Telnet(Host=>$host) or 
		die "Unable to connect to $host: ".($!?$!:$_)."\n";
}



#> DEBUG $t->dump_log("LOG");

$t->print("\n");

my @patterns;
$prompt_user="^Enter user name:";
$prompt_pass="^Enter Password:";
$prompt_cmd="^RPC-27>";
$prompt_confirm_yn="^.*\\(Y/N\\)\\?";

$patterns[0]=$prompt_user;
$patterns[1]=$prompt_pass;
$patterns[2]=$prompt_cmd;
$patterns[3]=$prompt_confirm_yn;

my $p_index;
my @data;

my $bt_num="";
my $bt_name="";
my $bt_state="";
my $bt_locked="";
my $exit=1;

($p_index,@data) = get_match @patterns;

#
# Set errmode after first get_match.  This allows for more descriptive errors
# when handling unexpected error conditions
#
$t->errmode(\&rpc_error);

# At this point, the username is unknown.  We'll just
# pass in an empty passwd so that we can get back to the 
# login prompt.  
#
# FIXME
# If this is the third login failure for this switch, an
# additional newline will need to be made sent.  This script
# does not handle that case at this time.  This will cause
# a timeout on read and cause this to fail.  Rerunning the
# script ought to work though.
if ($patterns[$p_index] eq $prompt_pass)
{
	$t->print("\n");
	($p_index,@data) = get_match @patterns;
}

# Enter user name:
#
# Depending how the RPC is configured, a user name may not be required.
# We will only deal with usernames if prompted.  
#
# If there is no user/passwd given as a parameter, but the switch
# expects one, rather than just fail, we will first try to
# get the switch in a known state 
my $warn_user="yes";
my $warn_passwd="yes";

$error_message = "Invalid user/password";

for (my $retrys=0; $patterns[$p_index] eq $prompt_user ; $retrys++)
{
	$warn_passwd = "yes";
	if(defined $user)
	{
		$t->print("$user\n");
		$warn_user = "no";
	}
	else
	{
		$t->print("\n");

	}
	($p_index,@data) = get_match @patterns;

	# Enter Password:
	#
	# Users don't have to have passwords either.  We will only check
	# that the user specified a password if we were prompted by the
	# RPC.
	if ($patterns[$p_index] eq $prompt_pass)
	{
		if(defined $passwd)
		{
			$t->print("$passwd\n");
			$warn_passwd = "no";
		}
		else
		{
			$t->print("\n");
		}

		($p_index,@data) = get_match @patterns;
	}


	#
	# If a valid user name is given, but not a valid password, we
	# will loop forever unless we limit the number of retries
	#
	# set the user to "" so we stop entering a valid username and
	# force the login proccess to fail
	#
	if ($retrys>2)
	{
		$user = "";
	}
	elsif ($retrys>10)
	{
		die "maximum retry count exceeded\n";
	}
}

#
# reset errmode to die()
#
$t->errmode("die");

# all through with the login/passwd.  If we see any other prompt it is an 
# error.
if ($patterns[$p_index] ne $prompt_cmd)
{
	$t->print("\n");
	die "bad state: '$patterns[$p_index]'";
}

if (defined $user && ($warn_user eq "yes"))
{
	warn "warning: user parameter ignored\n";
}

if (defined $passwd && ($warn_passwd eq "yes"))
{
	warn "warning: passwd parameter ignored\n";
}




# We are now logged in, no need for these patterns.  We'll strip these
# so that we don't have to keep searching for patterns that shouldn't
# appear.
shift @patterns;
shift @patterns;

# Get the current status of a particular outlet.  Explicitly pass
# the status command in case the RPC is not configured to report the
# status on each command completion.
$t->print("status\n");
($p_index,@data) = get_match @patterns;
($bt_num,$bt_name,$bt_state,$bt_locked) = parse_status $outlet,@data;

if (!defined $bt_name )
{
	# We have problems if there is not outlet named $outlet
	print "Outlet \'$outlet\' not found\n";
	$exit=1;
}
elsif ($action =~ /status/i)
{
	print "Outlet '$bt_name' is $bt_state and is ".
		(($bt_locked eq "")?"not ":"")."Locked\n";
	$exit=0;
}
elsif ($bt_locked ne "")
{
	# Report an error if an outlet is locked since we can't actually 
	# issue commands on a Locked outlet.  This will prevent false
	# successes.
	print "Outlet '$bt_name' is Locked\n";
	$exit=1;
}
elsif (($action =~ /on/i && $bt_state eq "On") ||
	($action =~ /off/i && $bt_state eq "Off") )
{
	# No need to issue the on/off command since we are already in 
	# the desired state
	print "Outlet '$bt_name' is already $bt_state\n";
	$exit=0;
}
elsif ($action =~ /o(n|ff)/i)
{
	# On/Off command
	$t->print("$action $bt_num\n");
	($p_index,@data) = get_match @patterns;
	
	# Confirmation prompting maybe enabled in the switch.  If it is,
	# we enter 'Y' for yes.
	if ($patterns[$p_index] eq $prompt_confirm_yn)
	{
		$t->print("y\n");
		($p_index,@data) = get_match @patterns;
	}

	$t->print("status\n");
	($p_index,@data) = get_match @patterns;

	($bt_num,$bt_name,$bt_state,$bt_locked) = parse_status $outlet,@data;
	
	if ($bt_state =~ /$action/i)
	{
		print "success: outlet='$outlet' action='$action'\n";
		$exit=0;
	}
	else
	{	
		print "fail: outlet='$outlet' action='$action'\n";
		$exit=1;
	}
}
elsif ($action =~ /reboot/i)
{
	# Reboot command
	$t->print("$action $bt_num\n");
	($p_index,@data) = get_match @patterns;
	
	# Confirmation prompting maybe enabled in the switch.  If it is,
	# we enter 'Y' for yes.
	if ($patterns[$p_index] eq $prompt_confirm_yn)
	{
		$t->print("y\n");
		($p_index,@data) = get_match @patterns;
	}

	# The reboot command is annoying.  It reports that the outlet will
 	# reboot in 9 seconds.  Then it has a countdown timer.  We first
	# look for the "Rebooting... 9" message, then we parse the remaining
	# output to verify that it reaches 0 without skipping anything.
	my $pass=0;
	foreach (@data)
	{
		chomp;
		my $line = $_;

		# There is a countdown timer that prints a number, then sleeps a 
		# second, then prints a backspace and then another number
		#
		# /^Rebooting\.\.\. 9\b8\b7\b6\b5\b4\b3\b2\b1\b0\b$/
		if($line =~/^Rebooting\.\.\..*0[\b]$/)
		{
			$pass=1;
			last;
		}
	}

	if ($pass)
	{
		print "success: outlet='$outlet' action='$action'\n";
		$exit=0;
	}
	else
	{
		print "fail: outlet='$outlet' action='$action'\n";
		$exit=1;
	}
}
else
{
	die "bad state";
}

# Clean up.  If we don't tell it to logout, then anybody else can log onto 
# the serial port and have access to the switch without authentication (when 
# enabled)
$t->print("logout\n");
$t->close;
exit $exit;
