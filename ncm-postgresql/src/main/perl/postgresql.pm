# ${license-info}
# ${developer-info}
# ${author-info}

#######################################################################
#
# NCM component for PostgreSQL
#
# ** Generated file : do not edit **
#
#######################################################################

package NCM::Component::postgresql;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;

use EDG::WP4::CCM::Element;

use File::Copy;
use File::Path;
use File::Compare;
## for units etc
use MIME::Base64;
use Digest::MD5 qw(md5_hex);

##########################################################################
sub Configure {
##########################################################################
  our ($self, $config) = @_;
  our (%v,%p); 
  my ($name,$real_exec,$serv,$sym,$link,$case_insensitive);
  my @all_names=("pg_script","pg_conf","pg_hba","pg_alter");
  foreach $name (@all_names) {
  	$p{$name}{changed} = 0;
  }	
  our $comp='postgresql';
  my $base = "/software/components/$comp";
  my $pg_version_suf = "-".fetch("$base/pg_version", "");
  my $pg_engine = fetch("$base/pg_engine", "/usr/bin/");
  my $fqdn = $config->getValue("/system/network/hostname").".".$config->getValue("/system/network/domainname");
  my $shortname = $config->getValue("/system/network/hostname");
  our $debug_print = "15";
  $debug_print = fetch("$base/config/debug_print",$debug_print);
  $self->info("Debug_print=$debug_print");


  ## proposed structure
  ## first generate all config in a way that does not depend on running subsystem. 
  ## All start/stop/restart/reload of services can be flagged and dealt with later.

  my ($pg_data_dir_create,$pg_dir);
  $pg_data_dir_create=0;
  ## this default value is used in check_status
  my $pg_script_name="POSTGRES_DUMMY_VALUE";
   
  my $pg_etc_init_def = "/etc/init.d/postgresql".$pg_version_suf;
  ## this one comes with the installation
  if (! -e $pg_etc_init_def) {
	  $self->error("$pg_etc_init_def not found. Check your postgres installation.");
  	  return 1;
  }

  ## set the startup script name
  $name="pg_script";
  $pg_script_name=fetch("$base/pg_script_name","postgresql");
  ## when using a different name for startup script, it uses a similar called file in /etc/sysconfig/pgsql
  ## just symlinking for the moment
  $p{$name}{service}=$pg_script_name;
  ## this one comes with ncm-chkconfig
  if (! -e "/etc/init.d/$pg_script_name") {
	  $self->error("/etc/init.d/$pg_script_name not found. Should have been here with ncm-chkconfig.");
  	  return 1;
  }
  
  $p{$name}{filename}="/etc/sysconfig/pgsql/$pg_script_name";
  $p{$name}{mode}="BASH_SOURCE";
  	
  $pg_dir = fetch("$base/pg_dir","/var/lib/pgsql");
  $v{$name}{PGDATA}="$pg_dir/data";
  $v{$name}{PGPORT}=fetch("$base/pg_port","5432");
  $v{$name}{PGLOG}="$pg_dir/pgstartup.log";
  dump_it($name,"WRITE");
    
  ## postgresql.conf
  $name="pg_conf";
  $p{$name}{mode}="PLAIN_TEXT";
  $p{$name}{filename}="$pg_dir/data/postgresql.conf";
  $p{$name}{write_empty}=0;
  $v{$name}{PURE_TEXT}=fetch("$base/postgresql_conf");

  ## pg_hba.conf
  $name="pg_hba";
  $p{$name}{mode}="PLAIN_TEXT";
  $p{$name}{filename}="$pg_dir/data/pg_hba.conf";
  $p{$name}{write_empty}=0;
  $v{$name}{PURE_TEXT}=fetch("$base/pg_hba");

  ## we're going to use this file to check if one should run the "ALTER ROLE" commands.
  ## if not, i think running pg_alter unnecessary might cause transfer errors.
  ## to protect the passwds, the file will contain md5 hashes of the psql commands
  $name="pg_alter";
  $p{$name}{mode}="MD5_HASH";
  $p{$name}{filename}="$pg_dir/data/pg_alter.ncm-$comp";
  $p{$name}{write_empty}=0;

  ## it's possible that $pg_dir/data doesn't yet exist.
  ## we assume this is only due to pre-init postgres
  if ((! -d "$pg_dir/data") || (! -f "$pg_dir/data/PG_VERSION")) {
		$pg_data_dir_create=1;
		$p{pg_conf}{changed}=1;
		$p{pg_hba}{changed}=1;
  } else {
		## ok, we're gonna do dummy write here and real write later
		dump_it("pg_conf");
		dump_it("pg_hba");
  }

##################################################################################
##################################################################################
## starting part 2. dynamic config.
## includes all service checks and config changes that need running services.
  pd("Checking current status. Will be the same status after the component finishes.");
  my $current_status = check_status($pg_script_name);
  pd("Current status: $current_status.");

  pd("Starting some additional checks.","i",15);
  ## other things that might go wrong. and need some rerunning of things:
  ## aha, another one: 
  my $moved_suffix="-moved-for-postgres-by-ncm-$comp".`date +%Y%m%d-%H%M%S`;
  chomp($moved_suffix);
  if ((-d "$pg_dir/data") && (! -f "$pg_dir/data/PG_VERSION")) {
  		## ok, postgres will never like this
		## can't believe it will be running
		stop_service($pg_script_name);
  		# non-destructive mode on
  		my $tmp_name_1="$pg_dir/data";
  		if (move($tmp_name_1,$tmp_name_1."$moved_suffix")) {
  			$self->info("Moved ".$tmp_name_1." to ".$tmp_name_1."$moved_suffix.");
		} else {
			## it will never work, but next time make sure all goes well
			$self->error("Can't move ".$tmp_name_1." to ".$tmp_name_1."$moved_suffix. Please clean up.");
			return 1;
		}
  }		
  pd("Starting real configuration.","i",15);
###############################################################
###############################################################
  ## remap flags to service calls
  my ($pgsql_restart,$pgsql_reload);

  $pgsql_reload = $p{pg_hba}{changed};
  $pgsql_restart=($p{pg_script}{changed} ||$p{pg_conf}{changed});

  	if ($pgsql_restart) {
  		$self->info("Restarting $pg_script_name.");
  		stop_service($pg_script_name);
  		if ($pg_data_dir_create) {
  			## create correct dir, which should now be created by the init script and restart
  			## there are no backup files
  			if (-d "$pg_dir/data") {
				## you should never get here
				$self->error("Directory $pg_dir/data exists but pg_data_dir_create is flagged?? Oops. Should not happen.");
				return 1;
			} else {
				## determine initialisation
				## starting from 8.2, initdb is a separate postgres call
				## lets assume postmaster is there
				my $cmd="$pg_engine/postmaster --version";
				my $out=`$cmd`;
				if ($out) {
					if ($out =~ m/(\d+)\.(\d+).(\d+)\s*$/) {
						my $doInitdb = 0;
						if (($1 > 8)){
							$doInitdb = 1;
						} elsif ($1 == 8) {
							if ($2 >= 2 ){
								$doInitdb = 1;
							}
						}
						if ($doInitdb) {
							## postgres 8.2+
							$self->info("Initdb $pg_script_name to trigger the initialisation (found release $1.$2.$3 > 8.2).");
							if (! initdb_service(1,$pg_script_name)) {
								## so the something during the start went wrong. stop component;
								$self->error("Something went very wrong during the initialisation of $pg_script_name. Exiting...");
								return 1;
							} else {	
								stop_service($pg_script_name);
							}	
						} else {
							$self->info("Starting $pg_script_name to trigger the initialisation (found release $1.$2.$3 < 8.2).");
							if (! start_service(1,$pg_script_name)) {
								## so the something during the start went wrong. stop component;
								$self->error("Something went very wrong during the initialisation of $pg_script_name. Exiting...");
								return 1;
							} else {	
								stop_service($pg_script_name);
							}	
						};
					} else {
						$self->error("Command \"$cmd\" returns \"$out\" but this script doesn't expect it. (If you think it's a bug, please conatct the maintainer of this component). Exiting...");
						return 1;
					};
				} else {
					$self->error("Command \"$cmd\" returns nothing (Probably doesn't exist). Exiting...");
					return 1;
				};
				
			}		
  		}

  		$name="pg_conf";	
		pd("p{$name}{changed}: ".$p{$name}{changed},"i","10");
		if ($p{$name}{changed}) {
			$self->info("Config of $name changed. Writing...");
			dump_it($name,"WRITE");
		}
		start_service(1,$pg_script_name);
  	}
	## do some additional checks:
	if (! -d "$pg_dir/data") {
		## you should really never get here
		$self->error("Directory $pg_dir/data does not exist. Initialisation must have failed. (2)");
		return 1;
	}
	## so now it should be at least startable, but actually should be already running here...
	## maybe nothing changed, but postgres was down.
	return 1 if (! abs_start_service($pg_script_name,"Going to start $pg_script_name, it's strange that is was down."));
	
  	if ($pgsql_reload) {
  		$self->info("Reloading $pg_script_name.");
  		$name="pg_hba";	
		pd("p{$name}{changed}: ".$p{$name}{changed},"i","10");
		if ($p{$name}{changed}) {
			$self->info("Config of $name changed. Writing...");
			dump_it($name,"WRITE");
		}
			
		if(! reload_service($pg_script_name)) {
			## this should also not happen. looks like a bad hba.conf file
			$self->error("$pg_script_name reload failed. Exiting...");
			return 1;
		}	
	}
	## so now it actually should be already running here...
	## maybe reload did something stupid
	return 1 if (! abs_start_service($pg_script_name,"Going to start $pg_script_name, it's strange that is was down after the reload."));

	## so now we have a running postgres
	
	## run the alter command
	if (check_status($pg_script_name)) {
		## it should be here
		if (! pg_alter("$base")) {
			$self->error("Something went wrong during the addition of roles and/or databases. This must be cleared first.");
			return 1;
		}	
	} 
	## can the alter script make postgres go down. probably not, anyway ...
	return 1 if (! abs_start_service($pg_script_name,"Going to start $pg_script_name, it's strange that is was down after running pg_alter."));
 
#############
############# save to assume that postgres is up and running here
#############




#######################################################################
#######################################################################
  # set postgres status to what it was
  pd("Setting status to what it was before the component ran.");
  if ($current_status) {
  	abs_start_service($pg_script_name);
  } else {
  	abs_stop_service($pg_script_name);
  }		 

 
############################################
## only subs now 
 
##########################################################################
sub pd {
##########################################################################
  my $text = shift;
  my $method = shift || "i";
  my $level = shift || "5";
  
  if ($level <= $debug_print) {
	  if ($method =~ m/^i/) { 
	  	$self->info($text);
	  } elsif ($method =~ m/^e/) {
	  	$self->error($text);
	  } elsif ($method =~ m/^w/) {
	  	$self->warn($text);
	  } else {
	  	$self->error("Unknown method $method in pd. Text was $text");
	  }
  }	  	
}

##########################################################################
sub sys2 {
##########################################################################
	## is a wrapper for system(). that's why it has these strange exitcodes
	## >0 is failure (the numeric values are not the same as in eg bash)
	## but it's the same as running with system($exec)
	my $exitcode=1;	
	my @argg=@_;

	my $exec=shift;
	my $use_system = shift || "true";
	## needs $use_system==0
	my $return_both = shift || "false"; 
	my $pd_val=5;
	if ($return_both eq "nothing") {
		$pd_val = "1000000";
	}	

	my $func = "sys2";
	pd("$func: function called with arg: @argg","i",$pd_val+5);

	my $output ="";
	
	if ($use_system eq "true") {
	    system($exec);
	    $exitcode=$?;
	    pd("$func:exec: $exec","i",$pd_val);
	    pd("$func:exitcode: $exitcode","i",$pd_val);
	} else {
	    if (! open(FILE,$exec." 2>&1 |")){
			pd("$func: exec=$exec: $!","e","i",$pd_val);
		} else {
			$output="";
			pd("$func: Processing FILE now","i",$pd_val+13);
			while(<FILE>) {
			    pd("$func: Processing FILE now: $_",,"i",$pd_val+13);
			    $output .= $_;
			}	
			close(FILE);
			$exitcode=$?;
			pd("$func:exec: $exec","i",$pd_val);
			pd("$func:output: ".$output,"i",$pd_val);
			pd("$func:exitcode: $exitcode","i",$pd_val);
	    }
	}
	if ( ($use_system ne "true") && ($return_both eq "true")) {
		return ($exitcode,$output);
	} else {		
		return $exitcode;	
	}	
}

##########################################################################
sub check_status {
##########################################################################
	my $func = "check_status";
	pd("$func: function called with arg: @_","i","10");
	
	## return: 1 is up, 0 is down
	my $service = shift;
	my $real_exec;
	my $ok = 1;	
	## check if postmaster is running
	$real_exec="ps ax|grep postmaster|grep -v grep";
	$ok = 0 if (sys2($real_exec));
	$real_exec="/etc/init.d/$service status";
	$ok = 0 if (sys2($real_exec));

	return $ok;	
}

##########################################################################
sub stop_service {
##########################################################################
	my $func = "stop_service";
	pd("$func: function called with arg: @_","i","10");

	my @services = @_;
	my ($se,$real_exec);
	foreach $se (@services) {
		## check status, if not up, don't stop
		if (check_status($se)) {
			$real_exec="/etc/init.d/$se stop";
			pd("Can't stop $se using $real_exec.","e") if (sys2($real_exec));
		}
	}
	my $exitcode=1;
	## recheck if everything is down now.
	foreach $se (@services) {
		## check status, if up, flag error
		if (check_status($se)) {
			$exitcode=0;
		}
	}
	return $exitcode;		
}

##########################################################################
sub reload_service {
##########################################################################
	my $func = "reload_service";
	pd("$func: function called with arg: @_","i","10");

	my @services = @_;
	my ($se,$real_exec);
	foreach $se (@services) {
		## check status, if not up, start
		if (check_status($se)) {
			$real_exec="/etc/init.d/$se reload";
			pd("Can't reload $se using $real_exec.","e") if (sys2($real_exec));
		} else {
			start_service(0,$se)
		}	
	}
	my $exitcode=1;
	## recheck if everything is up now.
	foreach $se (@services) {
		## check status, if down, flag error
		if (! check_status($se)) {
			$exitcode=0;
		}
	}
	return $exitcode;		
}

##########################################################################
sub start_service {
##########################################################################
	my $func = "start_service";
	pd("$func: function called with arg: @_","i","10");

	my ($force_restart,@services) = @_;
	my ($se,$real_exec);
	foreach $se (@services) {
		## check status, if up, don't start
		if (! check_status($se)) {
			$real_exec="/etc/init.d/$se start";
			pd("Can't start $se using $real_exec.","e") if (sys2($real_exec));	
		} elsif ($force_restart) {
			$self->error("Can't start $se: service is running. Forcing restart");
			$real_exec="/etc/init.d/$se restart";
			pd("Can't start $se using $real_exec.","e") if (sys2($real_exec));
		} else {
			pd("Won't start $se: service is running.")
		}	
	}
	my $exitcode=1;
	## recheck if everything is up now.
	foreach $se (@services) {
		## check status, if down, flag error
		if (! check_status($se)) {
			$exitcode=0;
		}
	}
	return $exitcode;	
}

##########################################################################
sub initdb_service {
##########################################################################
	my $func = "initdb_service";
	pd("$func: function called with arg: @_","i","10");

	my ($force_restart,@services) = @_;
	my ($se,$real_exec);
	foreach $se (@services) {
		## check status, if up, don't start
		if (! check_status($se)) {
			$real_exec="/etc/init.d/$se initdb";
			pd("Can't initdb $se using $real_exec.","e") if (sys2($real_exec));	
			## start it
			$real_exec="/etc/init.d/$se start";
			pd("Can't start $se using $real_exec.","e") if (sys2($real_exec));	
		} elsif ($force_restart) {
			$self->error("Can't start $se: service is running. Forcing restart");
			$real_exec="/etc/init.d/$se restart";
			pd("Can't start $se using $real_exec.","e") if (sys2($real_exec));
		} else {
			pd("Won't start $se: service is running.")
		}	
	}
	my $exitcode=1;
	## recheck if everything is up now.
	foreach $se (@services) {
		## check status, if down, flag error
		if (! check_status($se)) {
			$exitcode=0;
		}
	}
	return $exitcode;	
}


##########################################################################
sub abs_stop_service {
##########################################################################
	my $func = "abs_stop_service";
	pd("$func: function called with arg: @_","i","10");

	my $serv = shift;
	my $reason_1 = shift || "Stopping service $serv now.";
	$reason_1 .= " (ABS-mode)";
	my $reason_2 = shift || "Stopping service $serv failed. Something's really wrong. Exiting...";
	## check the status and shut it down
  	if (check_status($serv)) {
		pd($reason_1);
		stop_service($serv);
	}	
	## is $serv up?
	if (check_status($serv)) {
		## same story, you should never get here
		pd($reason_2,"e");
		return 0;
	} else {
		return 1;
	}	
}

##########################################################################
sub abs_start_service {
##########################################################################
	my $func = "abs_start_service";
	pd("$func: function called with arg: @_","i","10");

	my $serv = shift;
	my $reason_1 = shift || "Starting service $serv now.";
	$reason_1 .= " (ABS-mode)";
	my $reason_2 = shift || "Starting service $serv failed. Something's really wrong. Exiting...";
	## check the status and start it
  	if (! check_status($serv)) {
		pd($reason_1);
		start_service(0,$serv);
	}	
	## is $serv up?
	if (! check_status($serv)) {
		## same story, you should never get here
		pd($reason_2,"e");
		return 0;
	} else {
		return 1;
	}	
}

##########################################################################
sub fetch {
##########################################################################
  my $func = "fetch";
  pd("$func: function called with arg: @_","i","10");
  my $path = shift;
  my $default = shift || "";
  my $value;
  
  if ($config->elementExists($path)) {
  	$value = $config->getValue($path);
  } else {
  	$value = $default;
  }
  return $value;
} 


##########################################################################
sub slurp {
##########################################################################
	my $func = "slurp";
	pd("$func: function called with arg: @_","i","10");

	my $name=shift;
	my $new_base=shift;
	my $def_dir=shift;
	my $mode=$p{$name}{mode};
	pd("$func: Start with name=$name mode=$mode","i","10");

	## check for case insensitive
	my $capit=0;
	if ((exists $p{$name}{case_insensitive}) && (1 == $p{$name}{case_insensitive})) {
		$capit = 1;
	}	
    ## ok, lets see what we have here
    my @def_list=();  
    ## if $new_base is of the format file://, use that one
	if ($new_base =~ m/^file:\/\//) {
		$new_base =~ s/^file:\/\///;
		unshift @def_list, $new_base;
		$new_base=0;
	}
	
    my $n=0;
	## read all default files to be parsed BEFORE reading configured values
    while ($new_base && $config->elementExists($new_base."_def/".$n)) {
	  my $tmp = $config->getValue($new_base."_def/".$n);
      ## if $tmp doesn't start with /, add $def_dir
      if ($tmp !~ m/^\//) {
        $tmp = "$def_dir/$tmp";
      }
      if (-f $tmp) {
        unshift @def_list, $tmp;
      } else {
        $self->warn("$func: Default file $tmp from ".$new_base."_def/".$n." not found.");
      }
      $n++;
    }
    
    foreach my $tmp (@def_list) {
    	if ($mode =~ m/BASH_SOURCE/) {
			## ok, for BASH_SOURCE we need to do some more or get a real parser somewhere.
    		## we make the assumption that the files can be sourced whithout problems whithout interlinked variables
    		## also that the variables passed through quattor-config contain no other variables

			## in this run, values can be overwritten again by what's defined in the files. this is why the following needs to be run everytime
		    if ($new_base && $config->elementExists("$new_base")) {
				my $all = $config->getElement("$new_base");
				while ( $all->hasNextElement() ) {
					my $el = $all->getNextElement();
					my $el_name = $el->getName();
					my $el_val = $el->getValue();
					$el_name =~ tr/a-z/A-Z/ if $capit;
					## overwrite defaults or add new values
					$v{$name}{$el_name}=$el_val;
    	  		}
			} else {
		  		$self->warn("$func: Nothing set for $new_base (1).") if ($new_base);
			}
			
    		## snr all variables with values set in previous files/quattor config or leave them untouched.
    		my $tmp2=$tmp."-2";
    		open(FILE,$tmp) || pd("$func: Can't open $tmp: $!.","e",1);
    		open(OUT,"> $tmp2") || pd("$func: Can't open $tmp2 for writing: $!.","e",1);
    		while(<FILE>){
    			## shouldn't we filter out comments and whitespace here? For speed...
				 if (m/^\s*$/ || m/^\s*\#.*/) {
			        ## do nothing
			    } else {
			    	## we're replacing all usage of $x and ${x} with the values defined
	    			for my $key (keys(%{$v{$name}})) {
    					while (m/[^\\]?\$\{$key\}/) {
				            s/([^\\]?)\$\{$key\}/$1$v{$name}{$key}/;
      	  				}
        				while (m/[^\\]?\$$key\W?/) {
			        	    s/([^\\]?)\$$key(\W?)/$1$v{$name}{$key}$2/;
	        			}
    	    		}	
        			print OUT;
        		}	
			}
			close(FILE);
			close(OUT);    				
			    		
    	   	## to read config files that can be used to source the variables
	      	## here's an original approach to extract the values ;)
	      	my $exe="source $tmp2";
    	  	open(FILE, "/bin/bash 2>&1 -x -c \"$exe\" |") || $self->error("$func: /bin/bash 2>&1 -x -c \"$exe\" didn't run: $!");
	      	my $now=0;
    	  	while (<FILE>){
		  		s/\+\+ //g;
			  	s/\+ //g;
			  	if ($now) {
			      	chomp;
			      	my $i=index($_,"=");
			      	my $k = substr($_,0,$i);
			      	$k =~ tr/a-z/A-Z/ if $capit;
	    		  	$i++;
		    	  	my $va = substr($_,$i,length($_));
		    	  	## there's a difference between bash v2 and v3 when using +x and multiple lines. 
		    	  	## v3 adds single quotes (which is the correct thing todo btw)
		    	  	## they need to be removed though
		    	  	if (($va =~ m/^'/) && ($va =~ m/^'/)) {
				    	## begin and end have a single quote. they can be removed
				    	## AND later replaced by double quotes because this output contains nothing that needs single quotes
					    $va =~ s/^'//;
						$va =~ s/'$//;
					};
			      	$v{$name}{$k}=$va;
		  	  	}
	  		  	$now=1 if (m/^$exe/);
          	}
          	close FILE;
          	## small hack for export entries (as in pnfsSetup).
			## when a "export a=b" is passed through this, it will make 2 entries
			## one as "export a"="b" and one as "a"="b" and in that order. 
			## so for now, just remove the second one when we see the first one
			for my $k (keys %{$v{$name}}) {	
		      	if ($k =~ m/^export /) {
					pd("$func: export detected in key $k. trying to fix it...","i","15");
		      		$k =~ s/export //;
		      		delete $v{$name}{$k};
			  	}	
          	}
          	unlink($tmp2) || pd("Can't unlink $tmp2: $!","e",1);
       	} elsif ($mode =~ m/PLAIN_TEXT/) {
       		## just read everything in one string
       		open(FILE,$tmp)|| $self->error("$func: Can't open $tmp: $!");
       		my $now="";
		    while (<FILE>){
		    	$now .= $_;
		    }
		    close FILE;
		    $v{$name}{"PURE_TEXT"}=$now;
       } elsif ($mode =~ m/EQUAL_SPACE/) {  
       			## variables are read like "YY = ZZ"
		      open(FILE,$tmp)|| $self->error("$func: Can't open $tmp: $!");
		      while (<FILE>){
	    		  if (! m/^#/){
		    		  chomp;
				      my @all=split(/ = /,$_);
				  	  my $k = $all[0];
			    	  $k =~ tr/a-z/A-Z/ if $capit;
		    		  my $va = $all[1];
				      $v{$name}{$k}=$va;
				  }
		      }
		      close FILE;
       } elsif ($mode =~ m/MD5_HASH/) {  
       		## variables are read like "YY=ZZ"
		    open(FILE,$tmp)|| $self->error("$func: Can't open $tmp: $!");
		    while (<FILE>){
	    	  if (! m/^#/){
		    	chomp;
				my @all=split(/=/,$_);
				my $k = $all[0];
			    $k =~ tr/a-z/A-Z/ if $capit;
		    	my $va = $all[1];
				$v{$name}{$k}=$va;
			  }
		    }
		    close FILE;
       } else {
       		$self->error("$func: Using mode $mode, but doesn't match.");
       	}	   
  	}
    if ($new_base && $config->elementExists("$new_base")) {
		my $all = $config->getElement("$new_base");
		while ( $all->hasNextElement() ) {
			my $el = $all->getNextElement();
			my $el_name = $el->getName();
			my $el_val = $el->getValue();
			$el_name =~ tr/a-z/A-Z/ if $capit;
			## overwrite defaults or add new values
			$v{$name}{$el_name}=$el_val;
      	}
	} else {
	  $self->warn("$func: Nothing set for $new_base (2).") if ($new_base);
	}
	pd("$func: Stop with name=$name","i","10");
}


##########################################################################
sub dump_it {
##########################################################################
	my $func = "dump_it";
	pd("$func: function called with arg: @_","i",10);
	my $name = shift;
	my $extra_mode = shift || "DUMMY_WRITE_SET";

	my $file_name=$p{$name}{filename};
	my $mode=$p{$name}{mode}."_".$extra_mode;

	my $changed = 0;
	my $suffix=".back";
	pd("$func: Start with name=$name mode=$mode filename=$file_name","i","10");
		
    my $backup_file = $file_name.$suffix;
    my $backup_file_tmp = $backup_file.$suffix;
	if (-e $file_name) {
	    copy($file_name, $backup_file_tmp) || $self->error("Can't create backup $backup_file_tmp: $!");
	} else {
		pd("Can't create backup $backup_file_tmp: no current version found");
	}
	open(FILE,"> ".$file_name) || $self->error("Can't write to $file_name: $!");
	if ($mode !~ m/NO_COMMENT/) {
	  	print FILE "## Generated by ncm-$comp\n## DO NOT EDIT\n";
	}  	
	## ok, without the sort, you are garanteed to see some strange behaviour.
	foreach my $k (sort keys(%{$v{$name}})) {
		## ok, lets inplement some special values here:
		if ((exists $p{$name}{write_empty}) && ($p{$name}{write_empty} == 0) && ( "X".$v{$name}{$k} eq "X")) {
			## do nothing, print message
			$self->warn("Nothing specified for $name and key $k. Not writing to $file_name.")
		} elsif ($mode =~ m/PLAIN_TEXT/) {	
			print FILE $v{$name}{$k};
		} elsif ($mode =~ m/BASH_SOURCE/)  {
			## if there are spaces in the value, quote the whole line
			## in principle for source it doesn't matter, but in this way individual values can be used as names etc
			if ($v{$name}{$k} =~ m/ |=/) {
				print FILE "$k=\"$v{$name}{$k}\"\n";
			} else {
				print FILE "$k=$v{$name}{$k}\n";	
			}	
		} elsif ($mode =~ m/EQUAL_SPACE/) {
			print FILE "$k = $v{$name}{$k}\n";
		} elsif ($mode =~ m/ALL_POOL/) {
			print FILE "$func:  pool_host:$k\n";
			foreach my $k2 (keys %{$v{$name}{$k}}) {
			print FILE "$func:    pool_name: $k2\n";
				foreach my $k3 (keys %{$v{$name}{$k}{$k2}}) {
					if ($k3 eq "pgroup") {
						foreach my $vall (@{$v{$name}{$k}{$k2}{$k3}}) {
							print FILE "$func:      value $k3:$vall\n";
						}
					} else {
						print FILE "$func:      value $k3:".$v{$name}{$k}{$k2}{$k3}."\n";
					}	
				}
			}
		} elsif ($mode =~ m/MD5_HASH/) {
			## what could possibly go wrong here?
			my $md5=md5_hex($v{$name}{$k});
			print FILE "$k=$md5\n";
		}  else {
       		$self->error("Dump_it: Using mode $mode, but doesn't match.");
       	}	
	}	
    close(FILE);
    ## check for differences
	## if the file doesn't exists, compare will exit with -1, so this also checks existence of file
	if (compare($file_name,$backup_file_tmp) == 0) {
		## they're equal, remove backup
		unlink($backup_file_tmp) || $self->warn("Can't unlink ".$backup_file_tmp) ;
	} else {	
		if (-e $backup_file_tmp) {
			if ($mode =~ m/DUMMY_WRITE_SET/) {
				copy($backup_file_tmp, $file_name)  || $self->error("Can't move $backup_file_tmp to $file_name in mode $mode: $!");
			} else {
				copy($backup_file_tmp, $backup_file) || $self->error("Can't create backup $backup_file: $!");
			}	
		} else {
			if ($mode =~ m/DUMMY_WRITE_SET/) {
				unlink($file_name) || $self->error("Can't unlink $file_name in mode $mode: $!");
			}
		}		
		## flag the change here, action to be taken later
		$changed = 1;
	}

	if ($changed) {
		$p{$name}{changed}=1;
	} else {
		$p{$name}{changed}=0;
	}

	pd("$func: Stop with name=$name changed=$changed","i","10");
	return $changed;
}


##########################################################################
sub pg_alter {
##########################################################################
	my $func = "pg_alter";
	pd("$func: function called with arg: @_","i","10");

    my $new_base = shift;
    my $name="pg_alter";
    
	my $su;
	## taken from the init.d/postgresql script: For SELinux we need to use 'runuser' not 'su'
	if (-x "/sbin/runuser") {
	  $su="runuser";
	} else {
	  $su="su";
	}
	my $exitcode=1;
	## configure users/roles: list them with psql -t -c "SELECT rolname FROM pg_roles;"
	## a user is a role with the LOGIN attribute set
	my @all_roles=();
	open(TEMP,"$su -l postgres -c \"psql -t -c \\\"SELECT rolname FROM pg_roles;\\\"\" |")||pd("$func: SELECT rolname FROM pg_roles failed: $!","e","1");
	while(<TEMP>) {
	  chomp;
	  s/ //g;
	  push(@all_roles,$_);
	}
	close TEMP;
	my ($exi,$real_exec);
	my ($role,$rol,$r,$rol_opt);
	if ($config->elementExists("$new_base/roles")) {
	  my $roles = $config->getElement("$new_base/roles");
	  while ($roles->hasNextElement() ) {
	  	$role = $roles->getNextElement();
	  	$rol = $role->getName();
	  	## check if role exists, if not create it
	  	$exi=0;
	  	foreach $r (@all_roles) {
	  	  if ($r eq $rol) { $exi=1;}
	  	}
	  	if (! $exi) {
	  	  pd("$func: Role $rol does not exist. Creating...");
	  	  $real_exec="$su -l postgres -c \"psql -c \\\"CREATE ROLE \\\\\\\"$rol\\\\\\\"\\\"\"";
		  pd("$func: Executing $real_exec failed","e","1") if (sys2($real_exec));
	    }  
	  	## set defined attributes to role
	  	$rol_opt = $role->getValue();
	  	$v{$name}{$rol}=$rol_opt;
	  }
	}	
	
	dump_it($name,"WRITE");
	if ($p{$name}{changed}) {
		## apparently something has changed.
		pd("$func: Something changed to the roles attributes.");
		foreach $rol (keys %{$v{$name}}) {
		  	pd("$func: Role $rol: setting attributes...");
		  	$real_exec="$su -l postgres -c \"psql -c \\\"ALTER ROLE \\\\\\\"$rol\\\\\\\" ".$v{$name}{$rol}.";\\\"\"";
			## Passwds could be shown with this: $self->info("$real_exec");
			if (sys2($real_exec,"false","nothing")) {
				pd("$func: Executing ALTER ROLE $rol failed (attributes not shown for passwd reasons)","e","1");
				$exitcode=0;
			}	
		}
	}		

	my ($database,$datab,$datab_user,$datab_el,$datab_elem,$datab_file,$datab_sql_user,$datab_lang,$datab_lang_file);
	if ($config->elementExists("$new_base/databases")) {
	  my $databases = $config->getElement("$new_base/databases");
	  while ($databases->hasNextElement() ) {
	  	$database = $databases->getNextElement();
	    $datab = $database->getName();
	    $datab_el = $config->getElement("$new_base/databases/".$datab);
	    $datab_file = "";
        $datab_lang = "";
        $datab_lang_file = "";
	    $datab_sql_user= "REALLY_NOBODY";
	    while ($datab_el->hasNextElement() ) {
	    	$datab_elem = $datab_el->getNextElement();
		    $datab_user = $datab_elem->getValue() if ($datab_elem->getName() eq "user");
		    $datab_sql_user = $datab_elem->getValue() if ($datab_elem->getName() eq "sql_user");
		    $datab_file = $datab_elem->getValue() if ($datab_elem->getName() eq "installfile");
		    $datab_lang = $datab_elem->getValue() if ($datab_elem->getName() eq "lang");
		    $datab_lang_file = $datab_elem->getValue() if ($datab_elem->getName() eq "langfile");
		}
		$datab_sql_user = $datab_user if ($datab_sql_user eq "REALLY_NOBODY");
		$exitcode = create_pgdb($datab,$datab_user,$datab_file,$datab_lang,$datab_lang_file,$datab_sql_user);
	  }
	}  	    
  	return $exitcode;
}

##########################################################################
sub create_pgdb {
##########################################################################
	my $func = "create_pgdb";
	pd("$func: function called with arg: @_","i","10");
	
	my $datab = shift;
	my $datab_user = shift;
	my $datab_file = shift;
    my $datab_lang = shift;
    my $datab_lang_file = shift;
	my $datab_run_sql_user = shift ||$datab_user;
	my $exitcode = 1;
	
	my $su;
	## taken from the init.d/postgresql script: For SELinux we need to use 'runuser' not 'su'
	if (-x "/sbin/runuser") {
	  $su="runuser";
	} else {
	  $su="su";
	}
	
	## configure databases: list all databases with psql -t -c "SELECT datname FROM pg_database;"
    my @all_databases=();
	open(TEMP,"$su -l postgres -c \"psql -t -c \\\"SELECT datname FROM pg_database;\\\"\" |")||pd("$func: SELECT datname FROM pg_database failed: $!","e","1");
	while(<TEMP>) {
	  chomp;
	  s/ //g;
	  push(@all_databases,$_);
	}
	close TEMP;

	## check if database exists, if not create it
	my $exi=0;
	foreach my $d (@all_databases) {
		$exi=1 if ($d eq $datab);
	}
	if (! $exi) {
		pd("$func: Database $datab does not exist. Creating...");
		my $real_exec="$su -l postgres -c \"psql -c \\\"CREATE DATABASE \\\\\\\"$datab\\\\\\\" OWNER \\\\\\\"$datab_user\\\\\\\";\\\"\"";
		my ($exitcode,$output) = sys2($real_exec,"false","true");
		if (! $exitcode) {
			if (($datab_file ne "") && (-e $datab_file)) {
				pd("$func: Creating $datab: initialising with $datab_file.");
	    	  	$real_exec="$su -l postgres -c \"psql -U $datab_run_sql_user $datab -f $datab_file;\"";
	      		($exitcode,$output) = sys2($real_exec,"false","true");
				if ($exitcode) {
			  		pd("$func: Executing $real_exec failed:\n$output","e","1");
	    			$exitcode=0;
				}
	    	}
	    	## check for db lang
	    	if ($datab_lang ne "") {
                pd("$func: Creating $datab: setting lang $datab_lang.");
                $real_exec="$su -l postgres -c \"createlang $datab_lang $datab;\"";
                ($exitcode,$output) = sys2($real_exec,"false","true");
                if ($exitcode) {
                    pd("$func: Executing $real_exec failed:\n$output","e","1");
                    $exitcode=0;
                } else {
                    ## db lang init file
                    if (($datab_lang_file ne "") && (-e $datab_lang_file)) {
                        pd("$func: Creating $datab: initialising lang $datab_lang with $datab_lang_file.");
                        $real_exec="$su -l postgres -c \"psql -U $datab_run_sql_user $datab -f $datab_file;\"";
                        ($exitcode,$output) = sys2($real_exec,"false","true");
                        if ($exitcode) {
                            pd("$func: Executing $real_exec failed:\n$output","e","1");
                            $exitcode=0;
                        }
                    }
                }
            }
	    } else {
	    	pd("$func: Executing $real_exec failed with:\n$output","e","1");
	    }
	}  
	return $exitcode;
}


### real end of configure
  return 1;
}

