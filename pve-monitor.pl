#!/usr/bin/perl

#####################################################
#
#    Proxmox VE cluster monitoring tool
#
#####################################################
#
#   Script written by Damien PIQUET
#     damien.piquet@iutbeziers.fr || piqudam@gmail.com
#
#   Requires Net::Proxmox::VE librairy:
#     git://github.com/dpiquet/proxmox-ve-api-perl.git
#
# License Information:
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

use Net::Proxmox::VE;
use Data::Dumper;
use Getopt::Long;
use Switch;

my $configurationFile = './pve-monitor.conf';
my $pluginVersion = '1.0';

my %status = (
    'UNDEF'    => -1,
    'OK'       => 0,
    'WARNING'  => 1,
    'CRITICAL' => 2,
    'UNKNOWN'  => 3,
);

my %rstatus = reverse %status;

my %arguments = (
    'nodes'          => undef,
    'storages'       => undef,
    'openvz'         => undef,
    'qemu'           => undef,
    'conf'           => undef,
    'show_help'      => undef,
    'show_version'   => undef,
    'timeout'        => 5,
    'debug'          => undef,
);

sub usage {
    print "Usage: $0 [--nodes] [--storages] [--qemu] [--openvz] --conf <file>\n";
    print "\n";
    print "  --nodes\n";
    print "    Check the state of the cluster's members\n";
    print "  --storages\n";
    print "    Check the state of the cluster's storages\n";
    print "  --qemu\n";
    print "    Check the state of the cluster's Qemu virtual machines\n";
    print "  --openvz\n";
    print "    Check the state of the cluster's OpenVZ virtual machines\n";
}

sub is_number {
    ($_[0] =~ m/^[0-9]+$/) ? return 1 : return 0;
}

GetOptions ("nodes"     => \$arguments{nodes},
            "storages"  => \$arguments{storages},
            "openvz"    => \$arguments{openvz},
            "qemu"      => \$arguments{qemu},
            "conf=s"    => \$arguments{conf},
            'version|V' => \$arguments{show_version},
            'help|h'    => \$arguments{show_help},
            'timeout|t' => \$arguments{timeout},
            'debug'     => \$arguments{debug},
);

# set the alarm to timeout plugin
# before reading configuration file
local $SIG{ALRM} = sub {
    print "Plugin timed out !\n";
    exit $status{UNKNOWN};
};
alarm $arguments{timeout};

if (defined $arguments{show_version}) {
    print "$0 version $pluginVersion\n";
    exit $status{UNKNOWN};
}

if (defined $arguments{show_help}) {
    usage();
    exit $status{UNKNOWN};
}

if (! defined $arguments{conf}) {
    usage();
    exit $status{UNKNOWN};
}

# Arrays for objects to monitor
my @monitoredStorages;
my @monitoredNodes;
my @monitoredOpenvz;
my @monitoredQemus;

my $connected = 0;
my $host = undef;
my $username = undef;
my $password = undef;
my $realm = undef;
my $pve;

my $readingObject = 0;

# Read the configuration file
if (! open FILE, "<", "$arguments{conf}") {
    print "$!\n" if $arguments{debug};
    print "Cannot load configuration file $arguments{conf} !\n";
    exit $status{UNKNOWN};
}

while ( <FILE> ) {
    my $line = $_;

    # Skip commented lines (starting with #)
    next if $line =~ m/^#/i;

    # we got an object definition here !
    if ( $line =~ m/([\S]+)\s+([\S]+)\s+\{/i ) {
         switch ($1) {
             case "node" {
                 my $name            = $2;
                 my $warnCpu         = undef;
                 my $warnMem         = undef;
                 my $warnDisk        = undef;
                 my $critCpu         = undef;
                 my $critMem         = undef;
                 my $critDisk        = undef;
                 my $nAddr           = undef;
                 my $nPort           = 8006;
                 my $nUser           = undef;
                 my $nPwd            = undef;
                 my $nRealm          = 'pam';
                 my $warnMaxMemAlloc = undef;
                 my $critMaxMemAlloc = undef;

                 $readingObject = 1;

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^(\s+)?#/ );
                     if ( $objLine =~ m/([\S]+)\s+([\S]+)(\s+([\S]+))?/i ) {

                         switch ($1) {
                             case "cpu" {
                                 if ((is_number $2)and(is_number $4)) {
                                     $warnCpu = $2;
                                     $critCpu = $4;
                                 }
                                 else {
                                     print "Invalid CPU declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "mem" {
                                 if ((is_number $2)and(is_number $4)) {
                                     $warnMem = $2;
                                     $critMem = $4;
                                 }
                                 else {
                                     print "Invalid MEM declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "disk" {
                                 if ((is_number $2)and(is_number $4)) {
                                     $warnDisk = $2;
                                     $critDisk = $4;
                                 }
                                 else {
                                     print "Invalid DISK declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "mem_alloc" {
                                 $warnMaxMemAlloc = $2;
                                 $critMaxMemAlloc = $4;
                             }
                             case "address" {
                                 $nAddr = $2;
                             }
                             case "port" {
                                 if (is_number $2) {
                                     $nPort = $2;
                                 }
                                 else {
                                     print "Invalid PORT declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "monitor_account" {
                                 $nUser = $2;
                             }
                             case "monitor_password" {
                                 $nPwd = $2;
                             }
                             case "realm" {
                                 $nRealm = $2;
                             }
                             else {
                                 print "Invalid token $1 in $name definition !\n";
                                 exit $status{UNKNOWN};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !";
                             exit $status{UNKNOWN};
                         }

                         print "Loaded node $name\n"
                           if $arguments{debug};

                         $monitoredNodes[scalar(@monitoredNodes)] = ({
                                 name             => $name,
                                 address          => $nAddr,
                                 port             => $nPort,
                                 username         => $nUser,
                                 realm            => $nRealm,
                                 password         => $nPwd,
                                 warn_cpu         => $warnCpu,
                                 warn_mem         => $warnMem,
                                 warn_mem_alloc   => $warnMaxMemAlloc,
                                 warn_disk        => $warnDisk,
                                 crit_cpu         => $critCpu,
                                 crit_mem         => $critMem,
                                 crit_mem_alloc   => $critMaxMemAlloc,
                                 crit_disk        => $critDisk,
                                 cpu_status       => $status{OK},
                                 mem_status       => $status{OK},
                                 disk_status      => $status{OK},
                                 mem_alloc_status => $status{OK},
                                 alive            => 0,
                                 curmem           => undef,
                                 curdisk          => undef,
                                 curcpu           => undef,
                                 status           => $status{UNDEF},
                                 uptime           => undef,
                                 mem_alloc        => 0,
                                 max_mem          => undef,
                             },
                         );
                         
                         $readingObject = 0;
                         last;
                     }
                     else {
                         print "Invalid line " . chomp($objLine) . " at line $. !\n"
                           if $arguments{debug};
                     }
                 }
             }
             case "storage" {
                 my $name     = $2;
                 my $warnDisk = undef;
                 my $critDisk = undef;
                 my $node = undef;

                 $readingObject = 1;

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^#/i );
                     if ( $objLine =~ m/([\S]+)\s+([\S]+)(\s+([\S]+))?/i ) {
                         switch ($1) {
                             case "disk" {
                                 if ((is_number $2)and(is_number $4)) {
                                     $warnDisk = $2;
                                     $critDisk = $4;
                                 }
                                 else {
                                     print "Invalid DISK declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "node" {
                                 $node = $2;
                             }
                             else {
                                 print "Invalid token $1 in $name definition !\n";
                                 exit $status{UNKNOWN};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !";
                             exit $status{UNKNOWN};
                         }

                         if (! defined $node ) {
                             print "Invalid configuration, " . 
                                   "missing node in $name storage definition !\n";
                             exit $status{UNKNOWN};
                         }

                         print "Loaded storage $name\n"
                           if $arguments{debug};

                         $monitoredStorages[scalar(@monitoredStorages)] = ({
                                 name         => $name,
                                 node         => $node,
                                 warn_disk    => $warnDisk,
                                 crit_disk    => $critDisk,
                                 curdisk      => undef,
                                 disk_status  => $status{OK},
                                 status       => $status{UNDEF},
                             },
                         );
                         $readingObject = 0;
                         last;
                     }
                 }

             }
             case "openvz" {
                 my $name     = $2;
                 my $warnCpu  = undef;
                 my $warnMem  = undef;
                 my $warnDisk = undef;
                 my $critCpu  = undef;
                 my $critMem  = undef;
                 my $critDisk = undef;

                 $readingObject = 1;

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^#/i );
                     if ( $objLine =~ m/([\S]+)\s+([\S]+)\s+([\S]+)/i ) {
                         switch ($1) {
                             case "cpu" {
                                 if ((is_number $2) and (is_number $3)) {
                                     $warnCpu = $2;
                                     $critCpu = $3;
                                 }
                                 else {
                                     print "Invalid CPU declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "mem" {
                                 if ((is_number $2) and (is_number $3)) {
                                     $warnMem = $2;
                                     $critMem = $3;
                                 }
                                 else {
                                     print "Invalid MEM declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "disk" { 
                                 if ((is_number $2) and (is_number $3)) {
                                     $warnDisk = $2;
                                     $critDisk = $3;
                                 }
                                 else {
                                     print "Invalid DISK declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             else {
                                 print "Invalid token $1 in $name definition !\n";
                                 exit $status{UNKNOWN};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !";
                             exit $status{UNKNOWN};
                         }

                         print "Loaded openvz $name\n"
                           if $arguments{debug};

                         $monitoredOpenvz[scalar(@monitoredOpenvz)] = ({
                                 name         => $name,
                                 warn_cpu     => $warnCpu,
                                 warn_mem     => $warnMem,
                                 warn_disk    => $warnDisk,
                                 crit_cpu     => $critCpu,
                                 crit_mem     => $critMem,
                                 crit_disk    => $critDisk,
                                 alive        => undef,
                                 curmem       => undef,
                                 curdisk      => undef,
                                 curcpu       => undef,
                                 cpu_status   => $status{OK},
                                 mem_status   => $status{OK},
                                 disk_status  => $status{OK},
                                 status       => $status{UNDEF},
                                 uptime       => undef,
                                 node         => undef,
                             },
                         );
                         $readingObject = 0;
                         last;
                     }
                 }
             }
             case "qemu" {
                 my $name     = $2;
                 my $warnCpu  = undef;
                 my $warnMem  = undef;
                 my $warnDisk = undef;
                 my $critCpu  = undef;
                 my $critMem  = undef;
                 my $critDisk = undef;

                 $readingObject = 1;

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^#/i );
                     if ( $objLine =~ m/([\S]+)\s+([\S]+)\s+([\S]+)/i ) {
                         switch ($1) {
                             case "cpu" {
                                 if ((is_number $2)and(is_number $3)) {
                                     $warnCpu = $2;
                                     $critCpu = $3;
                                 }
                                 else {
                                     print "Invalid CPU declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "mem" {
                                 if ((is_number $2)and(is_number $3)) {
                                     $warnMem = $2;
                                     $critMem = $3;
                                 }
                                 else {
                                     print "Invalid MEM declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             case "disk" {
                                 if ((is_number $2)and(is_number $3)) {
                                     $warnDisk = $2;
                                     $critDisk = $3;
                                 }
                                 else {
                                     print "Invalid DISK declaration in $name definition\n";
                                     exit $status{UNKNOWN};
                                 }
                             }
                             else {
                                 print "Invalid token $1 in $name definition !\n";
                                 exit $status{UNKNOWN};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !\n";
                             exit $status{UNKNOWN};
                         }

                         print "Loaded qemu $name\n"
                           if $arguments{debug};

                         $monitoredQemus[scalar(@monitoredQemus)] = (
                             {
                                 name         => $name,
                                 warn_cpu     => $warnCpu,
                                 warn_mem     => $warnMem,
                                 warn_disk    => $warnDisk,
                                 crit_cpu     => $critCpu,
                                 crit_mem     => $critMem,
                                 crit_disk    => $critDisk,
                                 alive        => undef,
                                 curmem       => undef,
                                 curdisk      => undef,
                                 curcpu       => undef,
                                 cpu_status   => $status{OK},
                                 mem_status   => $status{OK},
                                 disk_status  => $status{OK},
                                 status       => $status{UNDEF},
                                 uptime       => undef,
                                 node         => undef,
                             },
                         );
                         $readingObject = 0;
                         last;
                     }
                 }
             }
             else {
                 print "Invalid token $1 in configuration file $arguments{conf} !\n";
                 exit $status{UNKNOWN};
             }
         }
    }
}

close(FILE);

if ( $readingObject ) {
    print "Invalid configuration ! (Probably missing '}' ) \n";
    exit $status{UNKNOWN};
}

# Reset alarm to give a value relative to the number of nodes
alarm ($arguments{timeout} * scalar(@monitoredNodes) + $arguments{timeout});

for($a = 0; $a < scalar(@monitoredNodes); $a++) {
    my $host     = $monitoredNodes[$a]->{address} or next;
    my $port     = $monitoredNodes[$a]->{port} or next;
    my $username = $monitoredNodes[$a]->{username} or next;
    my $password = $monitoredNodes[$a]->{password} or next;
    my $realm    = $monitoredNodes[$a]->{realm} or next;

    print "Trying " . $host . "...\n"
      if $arguments{debug};

    $pve = Net::Proxmox::VE->new(
        host     => $host,
        username => $username,
        password => $password,
        debug    => $arguments{debug},
        realm    => $realm,
        timeout  => $arguments{timeout},
    );

    next unless $pve->login;
    next unless $pve->check_login_ticket;
    next unless $pve->api_version_check;

    # Here we are connected, quit the loop
    print "Successfully connected to " . $host . " !\n"
      if $arguments{debug};

    $connected = 1;
    last;
}

if (! $connected ) {
    print "Could not connect to any server !";
    exit $status{UNKNOWN};
}

# list all ressources of the cluster
my $objects = $pve->get('/cluster/resources');

print "Found " . scalar(@$objects) . " objects:\n"
  if $arguments{debug};

# loop the objects to compare our definitions with the current state of the cluster
foreach my $item( @$objects ) { 
    switch ($item->{type}) {
        case "node" {
            # loop the node array to see if that one is monitored
            foreach my $mnode( @monitoredNodes ) {
                next unless ($item->{node} eq $mnode->{name});

                print "Found $mnode->{name} in resource list\n"
                  if $arguments{debug};

                # if a node is down, many values are not set
                if(defined $item->{uptime}) {
                    $mnode->{status}  = $status{OK};
                    $mnode->{uptime}  = $item->{uptime};
                    $mnode->{maxmem}  = $item->{maxmem};
 
                    $mnode->{curmem}  = sprintf("%.2f", $item->{mem} / $item->{maxmem} * 100)
                      if ($item->{maxmem} > 0);

                    $mnode->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100)
                      if ($item->{maxdisk} > 0);

                    $mnode->{curcpu}  = sprintf("%.2f", $item->{cpu} / $item->{maxcpu} * 100)
                      if ($item->{maxcpu} > 0);
                }
                else {
                    $mnode->{status}  = -1;
                    $mnode->{uptime}  = 0;
                    $mnode->{curmem}  = 0;
                    $mnode->{curdisk} = 0;
                    $mnode->{curcpu}  = 0;
                }

                last;
            }
        }
        case "storage" {
            foreach my $mstorage( @monitoredStorages ) {
                next unless ($item->{storage} eq $mstorage->{name});
                next unless ($item->{node} eq $mstorage->{node});

                print "Found $mstorage->{name} in resource list\n"
                  if $arguments{debug};

                if (defined $item->{disk} ) {
                    $mstorage->{status} = $status{OK};

                    $mstorage->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100)
                      if ($item->{maxdisk} > 0);
                }
                else {
                    $mstorage->{status}  = -1;
                    $mstorage->{curdisk} = 0;
                }

                last;
            }

            next;
        }
        case "openvz" {
            #loop monitored nodes to increase mem_hi_limit
            foreach my $mnode( @monitoredNodes ) {
                next unless $mnode->{name} eq $item->{node};

                if (defined $item->{status}) {
                    $mnode->{mem_alloc} += $item->{maxmem}
                      if ($item->{status} eq "running");
                }

                last;
            }

            foreach my $mopenvz( @monitoredOpenvz ) {
                next unless ($item->{name} eq $mopenvz->{name});

                print "Found $mopenvz->{name} in resource list\n"
                  if $arguments{debug};

                if (defined $item->{status}) {
                    $mopenvz->{status}  = $status{OK};
                    $mopenvz->{alive}   = $item->{status};
                    $mopenvz->{uptime}  = $item->{uptime};
                    $mopenvz->{node}    = $item->{node};

                    
                    $mopenvz->{curmem}  = sprintf("%.2f", $item->{mem} / $item->{maxmem} * 100)
                      if ($item->{maxmem} > 0);
                    

                    $mopenvz->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100)
                      if ($item->{maxdisk} > 0);

                    $mopenvz->{curcpu}  = sprintf("%.2f", $item->{cpu} / $item->{maxcpu} * 100)
                      if ($item->{maxcpu} > 0);

                }
                else {
                    $mopenvz->{alive}   = "on dead node";
                    $mopenvz->{uptime}  = 0;
                    $mopenvz->{curmem}  = 0;
                    $mopenvz->{curdisk} = 0;
                    $mopenvz->{curcpu}  = 0;
                }

                last;
            }
            next;
        }
        case "qemu" {
            #loop monitored nodes to increase mem_hi_limit
            foreach my $mnode( @monitoredNodes ) {
                next unless $mnode->{name} eq $item->{node};

                if (defined $item->{status}) {
                    $mnode->{mem_alloc} += $item->{maxmem}
                      if ($item->{status} eq "running");
                }

                last;
            } 

            foreach my $mqemu( @monitoredQemus ) {
                next unless ($item->{name} eq $mqemu->{name});

                print "Found $mqemu->{name} in resource list\n"
                  if $arguments{debug};

                if(defined $item->{status}) {
                    $mqemu->{status}  = $status{OK};
                    $mqemu->{alive}   = $item->{status};
                    $mqemu->{uptime}  = $item->{uptime};
                    $mqemu->{node}    = $item->{node};

                    $mqemu->{curmem}  = sprintf("%.2f", $item->{mem} / $item->{maxmem} * 100)
                      if ($item->{maxmem} > 0);

                    $mqemu->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100)
                      if ($item->{maxdisk});

                    $mqemu->{curcpu}  = sprintf("%.2f", $item->{cpu} / $item->{maxcpu} * 100)
                      if ($item->{maxcpu} > 0);
                }
                else {
                    $mqemu->{alive}   = "on dead node";
                    $mqemu->{uptime}  = 0;
                    $mqemu->{curmem}  = 0;
                    $mqemu->{curdisk} = 0;
                    $mqemu->{curcpu}  = 0;
                }

                last;
            }

            next;
        }
    }
}

# Finally, loop the monitored objects arrays to report situation
if (defined $arguments{nodes}) {
    my $statusScore = 0;
    my $workingNodes = 0;

    my $reportSummary = '';

    foreach my $mnode( @monitoredNodes ) {
        $statusScore += $mnode->{status};
        
        if ($mnode->{status} ne $status{UNDEF}) {
            # compute max memory usage
            my $mem_hi_limit = 0;
            $mem_hi_limit = sprintf("%.2f", $mnode->{mem_alloc} / $mnode->{maxmem} * 100)
              if ($mnode->{maxmem} > 0);

            if (defined $mnode->{warn_mem_alloc}) {
                $mnode->{mem_alloc_status} = $status{WARNING}
                  if ($mem_hi_limit > $mnode->{warn_mem_alloc});
            }

            if (defined $mnode->{crit_mem_alloc}) {
                $mnode->{mem_alloc_status} = $status{CRITICAL}
                  if ($mem_hi_limit > $mnode->{crit_mem_alloc});
            }

            if (defined $mnode->{warn_mem}) {
                $mnode->{mem_status} = $status{WARNING}
                  if ($mnode->{curmem} > $mnode->{warn_mem});
            }

            if (defined $mnode->{crit_mem}) {
                $mnode->{mem_status} = $status{CRITICAL}
                  if ($mnode->{curmem} > $mnode->{crit_mem});
            }

            if (defined $mnode->{warn_disk}) {
                $mnode->{disk_status} = $status{WARNING}
                  if ($mnode->{curdisk} > $mnode->{warn_disk});
            }

            if (defined $mnode->{crit_disk}) {
                $mnode->{disk_status} = $status{CRITICAL}
                  if ($mnode->{curdisk} > $mnode->{crit_disk});
            }

            if (defined $mnode->{warn_cpu}) {
                $mnode->{cpu_status} = $status{WARNING}
                  if ($mnode->{curcpu} > $mnode->{warn_cpu});
            }

            if (defined $mnode->{crit_cpu}) {
                $mnode->{crit_cpu} = $status{CRITICAL}
                  if ($mnode->{curcpu} > $mnode->{crit_cpu});
            }

            if ($mnode->{status} ne $status{UNDEF}) {
                $reportSummary .= "NODE $mnode->{name} $rstatus{$mnode->{status}} : " .
                                  "cpu $rstatus{$mnode->{cpu_status}} ($mnode->{curcpu}%), " . 
                                  "mem $rstatus{$mnode->{mem_status}} ($mnode->{curmem}%), " . 
                                  "disk $rstatus{$mnode->{disk_status}} ($mnode->{curdisk}%) " .
                                  "mem alloc $rstatus{$mnode->{mem_alloc_status}} ($mem_hi_limit%), " .
                                  "uptime $mnode->{uptime}\n";

                $workingNodes++
                  if $mnode->{status} eq $status{OK};
            }
            else {
                $reportSummary .= "NODE $mnode->{name} $rstatus{$status{CRITICAL}} : ".
                                  "node is out of cluster (dead?)\n";
            }

            $statusScore += $mnode->{cpu_status} +
                            $mnode->{mem_status} +
                            $mnode->{disk_status} +
                            $mnode->{mem_alloc_status};

            # Do not leave $statusScore at level unknown here
            $statusScore++ if $statusScore eq $status{UNKNOWN};
        }
        else {
            $reportSummary .= "NODE $mnode->{name} " .
                              "is in status $rstatus{$status{UNKNOWN}}\n";
        }
    }

    $statusScore = $status{CRITICAL}
      if (( $statusScore > $status{UNKNOWN}) or ($statusScore < 0));

    print "NODES $rstatus{$statusScore}  $workingNodes / " .
          scalar(@monitoredNodes) . " working nodes\n" . $reportSummary;

    exit $statusScore;
} elsif (defined $arguments{openvz}) {
    my $statusScore = 0;
    my $workingVms = 0;

    my $reportSummary = '';

    foreach my $mopenvz( @monitoredOpenvz ) {
        if ($mopenvz->{status} ne $status{UNDEF}) {

            if (defined $mopenvz->{warn_mem}) {
                $mopenvz->{mem_status} = $status{WARNING}
                  if ($mopenvz->{curmem} > $mopenvz->{warn_mem});
            }

            if (defined $mopenvz->{crit_mem}) {
                $mopenvz->{mem_status} = $status{CRITICAL}
                  if $mopenvz->{curmem} > $mopenvz->{crit_mem};
            }

            if (defined $mopenvz->{warn_disk}) {
                $mopenvz->{disk_status} = $status{WARNING}
                  if $mopenvz->{curdisk} > $mopenvz->{warn_disk};
            }

            if (defined $mopenvz->{crit_disk}) {
                $mopenvz->{disk_status} = $status{CRITICAL}
                  if $mopenvz->{curdisk} > $mopenvz->{crit_disk};
            }

            if (defined $mopenvz->{warn_cpu}) {
                $mopenvz->{cpu_status} = $status{WARNING}
                  if $mopenvz->{curcpu} > $mopenvz->{warn_cpu};
            }

            if (defined $mopenvz->{crit_cpu}) {
                $mopenvz->{cpu_status} = $status{CRITICAL}
                  if $mopenvz->{curcpu} > $mopenvz->{crit_cpu};
            }

            if (defined $mopenvz->{alive}) {
                if ($mopenvz->{alive} eq "running") {
                     $mopenvz->{status} = $status{OK};
                     $workingVms++;

                     $reportSummary .= "OPENVZ $mopenvz->{name} ($mopenvz->{node}) $rstatus{$mopenvz->{status}} : " .
                                       "cpu $rstatus{$mopenvz->{cpu_status}} ($mopenvz->{curcpu}%), " .
                                       "mem $rstatus{$mopenvz->{mem_status}} ($mopenvz->{curmem}%), " .
                                       "disk $rstatus{$mopenvz->{disk_status}} ($mopenvz->{curdisk}%) " .
                                       "uptime $mopenvz->{uptime}\n";
                }
                else {
                    $mopenvz->{status} = $status{CRITICAL};
                    $statusScore += $status{CRITICAL};

                    $reportSummary .= "OPENVZ $mopenvz->{name} $rstatus{$mopenvz->{status}} : VM is $mopenvz->{alive}\n";
                }
            }


            $statusScore += $mopenvz->{cpu_status} + $mopenvz->{mem_status} + $mopenvz->{disk_status};

            $statusScore++ if $statusScore eq $status{UNKNOWN};
        }
        else {
            $reportSummary .= "OPENVZ $mopenvz->{name} " .
                              "is in status $rstatus{$status{UNKNOWN}}\n";

            $statusScore += $status{UNKNOWN};
        }
    }

    $statusScore = $status{CRITICAL}
      if ($statusScore > $status{UNKNOWN});

    print "OPENVZ $rstatus{$statusScore} $workingVms / " .
          scalar(@monitoredOpenvz) . " working VMs\n" . $reportSummary;

    exit $statusScore;
} elsif (defined $arguments{storages}) {
    my $statusScore = 0;
    my $workingStorages = 0;

    my $reportSummary = '';

    foreach my $mstorage( @monitoredStorages ) {

        if ($mstorage->{status} eq -1) {
            $statusScore += $status{CRITICAL};

            $reportSummary .= "$mstorage->{name} ($mstorage->{node}) $rstatus{$status{CRITICAL}}: " .
                              "storage is on a dead node\n";
        }
        elsif ($mstorage->{status} ne $status{UNKNOWN}) {
            if (defined $mstorage->{warn_disk}) {
                $mstorage->{disk_status} = $status{WARNING}
                  if $mstorage->{curdisk} > $mstorage->{warn_disk};
            }

            if (defined $mstorage->{crit_disk}) {
                $mstorage->{disk_status} = $status{CRITICAL}
                  if $mstorage->{curdisk} > $mstorage->{crit_disk};
            }

            $reportSummary .= "STORAGE $mstorage->{name} ($mstorage->{node}) $rstatus{$mstorage->{status}} : " .
                              "disk $mstorage->{curdisk}%\n";

            $workingStorages++;

	    $statusScore += $mstorage->{disk_status};

            $statusScore++ if $statusScore eq $status{UNKNOWN};
        }
        else {
            $reportSummary .= "STORAGE $mstorage->{name} " .
                              "is in status $rstatus{$status{UNKNOWN}}\n";
        }
    }

    $statusScore = $status{CRITICAL}
      if ($statusScore > $status{UNKNOWN});

    print "STORAGE $rstatus{$statusScore} $workingStorages / " .
          scalar(@monitoredStorages) . " working storages\n" . $reportSummary;

    exit $statusScore;
} elsif (defined $arguments{qemu}) {
    my $statusScore = 0;
    my $workingVms = 0;

    my $reportSummary = '';

    foreach my $mqemu( @monitoredQemus ) {
        if ($mqemu->{status} ne $status{UNDEF}) {
            if (defined $mqemu->{warn_mem}) {
                $mqemu->{mem_status} = $status{WARNING}
                  if $mqemu->{curmem} > $mqemu->{warn_mem};
            }

            if (defined $mqemu->{crit_mem}) {
                $mqemu->{mem_status} = $status{CRITICAL}
                  if $mqemu->{curmem} > $mqemu->{crit_mem};
            }

            if (defined $mqemu->{warn_disk}) {
                $mqemu->{disk_status} = $status{WARNING}
                  if $mqemu->{curdisk} > $mqemu->{warn_disk};
            }

            if (defined $mqemu->{crit_disk}) {
                $mqemu->{disk_status} = $status{CRITICAL}
                  if $mqemu->{curdisk} > $mqemu->{crit_disk};
            }

            if (defined $mqemu->{warn_cpu}) {
                $mqemu->{cpu_status} = $status{WARNING}
                  if $mqemu->{curcpu} > $mqemu->{warn_cpu};
            }

            if (defined $mqemu->{crit_cpu}) {
                $mqemu->{cpu_status} = $status{CRITICAL}
                  if $mqemu->{curcpu} > $mqemu->{crit_cpu};
            }

            if ($mqemu->{alive} eq "running") {
                $mqemu->{status} = $status{OK};
                $workingVms++;

                $reportSummary .= "QEMU $mqemu->{name} ($mqemu->{node}) $rstatus{$mqemu->{status}} : " .
                                  "cpu $rstatus{$mqemu->{cpu_status}} ($mqemu->{curcpu}%), " .
                                  "mem $rstatus{$mqemu->{mem_status}} ($mqemu->{curmem}%), " .
                                  "disk $rstatus{$mqemu->{disk_status}} ($mqemu->{curdisk}%) " .
                                  "uptime $mqemu->{uptime}\n";
            }
            else {
                $mqemu->{status} = $status{CRITICAL};

                $reportSummary .= "QEMU $mqemu->{name} $rstatus{$mqemu->{status}} : VM is $mqemu->{alive}\n";
                $statusScore += $status{CRITICAL};
                $mqemu->{status} = $status{CRITICAL};
            }

            $statusScore += $mqemu->{cpu_status} + $mqemu->{mem_status} + $mqemu->{disk_status};


            $statusScore++ if $statusScore eq $status{UNKNOWN};
        }
        else {
            $reportSummary .= "QEMU $mqemu->{name} " .
                              "is in status $rstatus{$status{UNKNOWN}}\n";

            $statusScore += $status{UNKNOWN};
        }
    }

    $statusScore = $status{CRITICAL}
      if ($statusScore > $status{UNKNOWN});

    print "QEMU $rstatus{$statusScore} $workingVms / " .
          scalar(@monitoredQemus) . " working VMs\n" .
          $reportSummary;

    exit $statusScore;
} else {
    usage();
    exit $status{UNKNOWN};
}
