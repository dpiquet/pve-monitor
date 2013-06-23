#!/usr/bin/perl

#####################################################
#
#    Proxmox VE cluster monitoring tool
#
#####################################################
#
#   Script written by Damien PIQUET  damien.piquet@iutbeziers.fr || piqudam@gmail.com
#
#   Requires Net::Proxmox::VE librairy: git://github.com/dpiquet/proxmox-ve-api-perl.git
#

use strict;
use warnings;

use lib './lib';
use Net::Proxmox::VE;
use Data::Dumper;
use Getopt::Long;
use Switch;

my $debug = 1;
my $timeout = 5;
my $configurationFile = './pve-monitor.conf';

my %status = (
    'ok'       => 0,
    'warning'  => 1,
    'critical' => 2,
    'unknown'  => 3,
);

my %rstatus = reverse %status;

my %arguments = (
    'nodes'    => undef,
    'storages' => undef,
    'openvz'   => undef,
    'qemu'     => undef,
    'conf'     => undef,
);

sub usage {
    print "Usage: $0 [--node] [--storage] [--qemu] [--openvz] --conf <file>\n";
}

GetOptions ("nodes"    => \$arguments{nodes},
            "storages" => \$arguments{storages},
            "openvz"   => \$arguments{openvz},
            "qemu"     => \$arguments{qemu},
            "conf=s"     => \$arguments{conf},
);

if (! defined $arguments{conf}) {
    usage();
    exit $status{unknown};
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
    print "$!\n" if $debug;
    print "Cannot load configuration file $arguments{conf} !\n";
    exit $status{unknown};
}

while ( <FILE> ) {
    my $line = $_;

    # Skip commented lines (starting with #)
    next if $line =~ m/^#/i;

    # we got an object definition here !
    if ( $line =~ m/([\w\/]+)\s+([\w\.]+)\s+\{/i ) {
         switch ($1) {
             case "node" {
                 my $name     = $2;
                 my $warnCpu  = undef;
                 my $warnMem  = undef;
                 my $warnDisk = undef;
                 my $critCpu  = undef;
                 my $critMem  = undef;
                 my $critDisk = undef;
                 my $nAddr    = undef;
                 my $nPort    = 8006;
                 my $nUser    = undef;
                 my $nPwd     = undef;
                 my $nRealm   = 'pam';

                 $readingObject = 1;

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^#/i );
                     if ( $objLine =~ m/([\w\.]+)\s+([\w\.]+)(\s+([\w\.]+))?/i ) {

                         switch ($1) {
                             case "cpu" {
                                 $warnCpu = $2;
                                 $critCpu = $3;
                             }
                             case "mem" {
                                 $warnMem = $2;
                                 $critMem = $3;
                             }
                             case "disk" {
                                 $warnDisk = $2;
                                 $critDisk = $3;
                             }
                             case "address" {
                                 $nAddr = $2;
                             }
                             case "port" {
                                 $nPort = $2;
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
                                 exit $status{unknown};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !";
                             exit $status{unknown};
                         }

                         print "Loaded node $name\n"
                           if $debug;

                         $monitoredNodes[scalar(@monitoredNodes)] = ({
                                 name         => $name,
                                 address      => $nAddr,
                                 port         => $nPort,
                                 username     => $nUser,
                                 realm        => $nRealm,
                                 password     => $nPwd,
                                 warn_cpu     => $warnCpu,
                                 warn_mem     => $warnMem,
                                 warn_disk    => $warnDisk,
                                 crit_cpu     => $critCpu,
                                 crit_mem     => $critMem,
                                 crit_disk    => $critDisk,
                                 cpu_status   => $status{ok},
                                 mem_status   => $status{ok},
                                 disk_status  => $status{ok},
                                 alive        => 0,
                                 curmem       => undef,
                                 curdisk      => undef,
                                 curcpu       => undef,
                                 status       => $status{unknown},
                                 uptime       => undef,
                             },
                         );
                         
                         $readingObject = 0;
                         last;
                     }
                 }
             }
             case "storage" {
                 my $name     = $2;
                 my $warnDisk = undef;
                 my $critDisk = undef;

                 $readingObject = 1;

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^#/i );
                     if ( $objLine =~ m/([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)/i ) {
                         switch ($1) {
                             case "disk" {
                                 $warnDisk = $2;
                                 $critDisk = $3;
                             }
                             else {
                                 print "Invalid token $1 in $name definition !\n";
                                 exit $status{unknown};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !";
                             exit $status{unknown};
                         }

                         print "Loaded storage $name\n"
                           if $debug;

                         $monitoredStorages[scalar(@monitoredStorages)] = ({
                                 name         => $name,
                                 warn_disk    => $warnDisk,
                                 crit_disk    => $critDisk,
                                 curdisk      => undef,
                                 disk_status  => $status{ok},
                                 status       => $status{unknown},
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
                     if ( $objLine =~ m/([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)/i ) {
                         switch ($1) {
                             case "cpu" {
                                 $warnCpu = $2;
                                 $critCpu = $3;
                             }
                             case "mem" {
                                 $warnMem = $2;
                                 $critMem = $3;
                             }
                             case "disk" {
                                 $warnDisk = $2;
                                 $critDisk = $3;
                             }
                             else {
                                 print "Invalid token $1 in $name definition !\n";
                                 exit $status{unknown};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !";
                             exit $status{unknown};
                         }

                         print "Loaded openvz $name\n"
                           if $debug;

                         $monitoredOpenvz[scalar(@monitoredOpenvz)] = ({
                                 name         => $name,
                                 warn_cpu     => $warnCpu,
                                 warn_mem     => $warnMem,
                                 warn_disk    => $warnDisk,
                                 crit_cpu     => $critCpu,
                                 crit_mem     => $critMem,
                                 crit_disk    => $critDisk,
                                 alive        => 0,
                                 curmem       => undef,
                                 curdisk      => undef,
                                 curcpu       => undef,
                                 cpu_status   => $status{ok},
                                 mem_status   => $status{ok},
                                 disk_status  => $status{ok},
                                 status       => $status{unknown},
                                 uptime       => undef,
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
                     if ( $objLine =~ m/([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)/i ) {
                         switch ($1) {
                             case "cpu" {
                                 $warnCpu = $2;
                                 $critCpu = $3;
                             }
                             case "mem" {
                                 $warnMem = $2;
                                 $critMem = $3;
                             }
                             case "disk" {
                                 $warnDisk = $2;
                                 $critDisk = $3;
                             }
                             else {
                                 print "Invalid token $1 in $name definition !\n";
                                 exit $status{unknown};
                             }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         if (! defined $name ) {
                             print "Invalid configuration !\n";
                             exit $status{unknown};
                         }

                         print "Loaded qemu $name\n"
                           if $debug;

                         $monitoredQemus[scalar(@monitoredQemus)] = (
                             {
                                 name         => $name,
                                 warn_cpu     => $warnCpu,
                                 warn_mem     => $warnMem,
                                 warn_disk    => $warnDisk,
                                 crit_cpu     => $critCpu,
                                 crit_mem     => $critMem,
                                 crit_disk    => $critDisk,
                                 alive        => 0,
                                 curmem       => undef,
                                 curdisk      => undef,
                                 curcpu       => undef,
                                 cpu_status   => $status{ok},
                                 mem_status   => $status{ok},
                                 disk_status  => $status{ok},
                                 status       => $status{unknown},
                                 uptime       => undef,
                             },
                         );
                         $readingObject = 0;
                         last;
                     }
                 }
             }
             else {
                 print "Invalid token $1 in configuration file $arguments{conf} !\n";
                 exit $status{unknown};
             }
         }
    }
}

close(FILE);

if ( $readingObject ) {
    print "Invalid configuration ! (Probably missing '}' ) \n";
    exit $status{unknown};
}   

for($a = 0; $a < scalar(@monitoredNodes); $a++) {
    my $host     = $monitoredNodes[$a]->{address} or next;
    my $port     = $monitoredNodes[$a]->{port} or next;
    my $username = $monitoredNodes[$a]->{username} or next;
    my $password = $monitoredNodes[$a]->{password} or next;
    my $realm    = $monitoredNodes[$a]->{realm} or next;

    print "Trying " . $host . "...\n"
      if $debug;

    $pve = Net::Proxmox::VE->new(
        host     => $host,
        username => $username,
        password => $password,
        debug    => $debug,
        realm    => $realm,
        timeout  => $timeout,
    );

    next unless $pve->login;
    next unless $pve->check_login_ticket;
    next unless $pve->api_version_check;

    # Here we are connected, quit the loop
    print "Successfully connected to " . $host . " !\n"
      if $debug;

    $connected = 1;
    last;
}

if (! $connected ) {
    print "Could not connect to any server !";
    exit $status{unknown};
}

# list all ressources of the cluster
my $objects = $pve->get('/cluster/resources');

print "Found " . scalar(@$objects) . " objects:\n"
  if $debug;

# loop the objects to compare our definitions with the current state of the cluster
foreach my $item( @$objects ) { 
    switch ($item->{type}) {
        case "node" {
            # loop the node array to see if that one is monitored
            foreach my $mnode( @monitoredNodes ) {
                next unless ($item->{node} eq $mnode->{name});

                print "Found $mnode->{name} in resource list\n"
                  if $debug;

                $mnode->{status}  = $status{ok};
                $mnode->{curmem}  = sprintf("%.2f", $item->{mem} / $item->{maxmem} * 100);
                $mnode->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100);
                $mnode->{curcpu}  = sprintf("%.2f", $item->{cpu} / $item->{maxcpu} * 100);
            }
        }
        case "storage" {
            foreach my $mstorage( @monitoredStorages ) {
                next unless ($item->{storage} eq $mstorage->{name});

                print "Found $mstorage->{name} in resource list\n"
                  if $debug;

                $mstorage->{status} = $status{ok};

                $mstorage->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100);
            }

            next;
        }
        case "openvz" {
            foreach my $mopenvz( @monitoredOpenvz ) {
                next unless ($item->{name} eq $mopenvz->{name});

                print "Found $mopenvz->{name} in resource list\n"
                  if $debug;

                $mopenvz->{status} = $status{critical}
                  if $item->{status} eq 'stopped';

                $mopenvz->{status} = $status{warning}
                  if $item->{status} eq 'suspend';

                $mopenvz->{status} = $status{ok}
                  if $item->{status} eq 'running';

                $mopenvz->{curmem}  = sprintf("%.2f", $item->{mem} / $item->{maxmem} * 100);
                $mopenvz->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100);
                $mopenvz->{curcpu}  = sprintf("%.2f", $item->{cpu} / $item->{maxcpu} * 100);
            }
            next;
        }
        case "qemu" {
            foreach my $mqemu( @monitoredQemus ) {
                next unless ($item->{name} eq $mqemu->{name});

                print "Found $mqemu->{name} in resource list\n"
                  if $debug;

                $mqemu->{status} = $status{critical}
                  if $item->{status} eq 'stopped';

                $mqemu->{status} = $status{warning}
                  if $item->{status} eq 'suspend';

                $mqemu->{status} = $status{ok}
                  if $item->{status} eq 'running';

                $mqemu->{curmem}  = sprintf("%.2f", $item->{mem} / $item->{maxmem} * 100);
                $mqemu->{curdisk} = sprintf("%.2f", $item->{disk} / $item->{maxdisk} * 100);
                $mqemu->{curcpu}  = sprintf("%.2f", $item->{cpu} / $item->{maxcpu} * 100);
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
        
        if ($mnode->{status} ne $status{unknown}) {
            if (defined $mnode->{warn_mem}) {
                $mnode->{mem_status} = $status{warning}
                  if ($mnode->{curmem} > $mnode->{warn_mem});
            }

            if (defined $mnode->{crit_mem}) {
                $mnode->{mem_status} = $status{critical}
                  if ($mnode->{curmem} > $mnode->{crit_mem});
            }

            if (defined $mnode->{warn_disk}) {
                $mnode->{disk_status} = $status{warning}
                  if ($mnode->{curdisk} > $mnode->{warn_disk});
            }

            if (defined $mnode->{crit_disk}) {
                $mnode->{disk_status} = $status{critical}
                  if ($mnode->{curdisk} > $mnode->{crit_disk});
            }

            if (defined $mnode->{warn_cpu}) {
                $mnode->{cpu_status} = $status{warning}
                  if ($mnode->{curcpu} > $mnode->{warn_cpu});
            }

            if (defined $mnode->{crit_cpu}) {
                $mnode->{crit_cpu} = $status{warning}
                  if ($mnode->{curcpu} > $mnode->{crit_cpu});
            }

            $reportSummary .= "NODE $mnode->{name} $rstatus{$mnode->{status}} : " .
                              "cpu $rstatus{$mnode->{cpu_status}} ($mnode->{curcpu}%), " . 
                              "mem $rstatus{$mnode->{mem_status}} ($mnode->{curmem}%), " . 
                              "disk $rstatus{$mnode->{disk_status}} ($mnode->{curdisk}%)\n";

            $workingNodes++;

            $statusScore += $mnode->{cpu_status} + $mnode->{mem_status} + $mnode->{disk_status};

            # Do not leave $statusScore at level unknown here
            $statusScore++ if $statusScore eq $status{unknown};
        }
        else {
            $reportSummary .= "NODE $mnode->{name} " .
                              "is in status $rstatus{$status{unknown}}\n";
        }
    }

    $statusScore = $status{critical}
      if ( $statusScore > $status{unknown});

    print "NODES $rstatus{$statusScore}  $workingNodes / " .
          scalar(@monitoredNodes) . "\n" . $reportSummary;

    exit $statusScore;
} elsif (defined $arguments{openvz}) {
    my $statusScore = 0;
    my $workingVms = 0;

    my $reportSummary = '';

    foreach my $mopenvz( @monitoredOpenvz ) {
        if ($mopenvz->{status} ne $status{unknown}) {

            if (defined $mopenvz->{warn_mem}) {
                $mopenvz->{mem_status} = $status{warning}
                  if ($mopenvz->{curmem} > $mopenvz->{warn_mem});
            }

            if (defined $mopenvz->{crit_mem}) {
                $mopenvz->{mem_status} = $status{critical}
                  if $mopenvz->{curmem} > $mopenvz->{crit_mem};
            }

            if (defined $mopenvz->{warn_disk}) {
                $$mopenvz->{disk_status} = $status{warning}
                  if $mopenvz->{curdisk} > $mopenvz->{warn_disk};
            }

            if (defined $mopenvz->{crit_disk}) {
                $mopenvz->{disk_status} = $status{critical}
                  if $mopenvz->{curdisk} > $mopenvz->{crit_disk};
            }

            if (defined $mopenvz->{warn_cpu}) {
                $mopenvz->{cpu_status} = $status{warning}
                  if $mopenvz->{curcpu} > $mopenvz->{warn_cpu};
            }

            if (defined $mopenvz->{crit_cpu}) {
                $mopenvz->{cpu_status} = $status{critical}
                  if $mopenvz->{curcpu} > $mopenvz->{crit_cpu};
            }

            $reportSummary .= "OPENVZ $mopenvz->{name} $rstatus{$mopenvz->{status}} : " .
                              "cpu $rstatus{$mopenvz->{cpu_status}} ($mopenvz->{curcpu}%), " .
                              "mem $rstatus{$mopenvz->{mem_status}} ($mopenvz->{curmem}%), " .
                              "disk $rstatus{$mopenvz->{disk_status}} ($mopenvz->{curdisk}%)\n";

            $workingVms++;

            $statusScore += $mopenvz->{cpu_status} + $mopenvz->{mem_status} + $mopenvz->{disk_status};

            $statusScore++ if $statusScore eq $status{unknown};
        }
        else {
            $reportSummary .= "OPENVZ $mopenvz->{name} " .
                              "is in status $rstatus{$status{unknown}}\n";
        }
    }

    $statusScore = $status{critical}
      if ($statusScore > 3);

    print "OPENVZ $rstatus{$statusScore} $workingVms / " .
          scalar(@monitoredOpenvz) . "\n" . $reportSummary;

    exit $statusScore;
} elsif (defined $arguments{storages}) {
    my $statusScore = 0;
    my $workingStorages = 0;

    my $reportSummary = '';

    foreach my $mstorage( @monitoredStorages ) {
        if ($mstorage->{status} ne $status{unknown}) {
            if (defined $mstorage->{warn_disk}) {
                $mstorage->{disk_status} = $status{warning}
                  if $mstorage->{curdisk} > $mstorage->{warn_disk};
            }

            if (defined $mstorage->{crit_disk}) {
                $mstorage->{disk_status} = $status{critical}
                  if $mstorage->{curdisk} > $mstorage->{crit_disk};
            }

            $reportSummary .= "STORAGE $mstorage->{name} $rstatus{$mstorage->{status}} : " .
                              "disk $mstorage->{curdisk}%\n";

            $workingStorages++;

	    $statusScore += $mstorage->{disk_status};

            $statusScore++ if $statusScore eq $status{unknown};
        }
        else {
            $reportSummary .= "STORAGE $mstorage->{name} " .
                              "is in status $rstatus{$status{unknown}}\n";
        }
    }

    $statusScore = $status{critical}
      if ($statusScore > 3);

    print "STORAGE $rstatus{$statusScore} $workingStorages / " .
          scalar(@monitoredStorages) . "\n" . $reportSummary;

    exit $statusScore;
} elsif (defined $arguments{qemu}) {
    my $statusScore = 0;
    my $workingVms = 0;

    my $reportSummary = '';

    foreach my $mqemu( @monitoredQemus ) {
        if ($mqemu->{status} ne $status{unknown}) {
            if (defined $mqemu->{warn_mem}) {
                $mqemu->{mem_status} = $status{warning}
                  if $mqemu->{curmem} > $mqemu->{warn_mem};
            }

            if (defined $mqemu->{crit_mem}) {
                $mqemu->{mem_status} = $status{critical}
                  if $mqemu->{curmem} > $mqemu->{crit_mem};
            }

            if (defined $mqemu->{warn_disk}) {
                $mqemu->{disk_status} = $status{warning}
                  if $mqemu->{curdisk} > $mqemu->{warn_disk};
            }

            if (defined $mqemu->{crit_disk}) {
                $mqemu->{disk_status} = $status{critical}
                  if $mqemu->{curdisk} > $mqemu->{crit_disk};
            }

            if (defined $mqemu->{warn_cpu}) {
                $mqemu->{cpu_status} = $status{warning}
                  if $mqemu->{curcpu} > $mqemu->{warn_cpu};
            }

            if (defined $mqemu->{crit_cpu}) {
                $mqemu->{cpu_status} = $status{critical}
                  if $mqemu->{curcpu} > $mqemu->{crit_cpu};
            }

            $statusScore += $mqemu->{cpu_status} + $mqemu->{mem_status} + $mqemu->{disk_status};

            $reportSummary .= "QEMU $mqemu->{name} $rstatus{$mqemu->{status}} : " .
                              "cpu $rstatus{$mqemu->{cpu_status}} ($mqemu->{curcpu}%), " .
                              "mem $rstatus{$mqemu->{mem_status}} ($mqemu->{curmem}%), " .
                              "disk $rstatus{$mqemu->{disk_status}} ($mqemu->{curdisk}%)\n";

            $statusScore++ if $statusScore eq $status{unknown};

            $workingVms++;
        }
        else {
            $reportSummary .= "QEMU $mqemu->{name} " .
                              "is in status $rstatus{$status{unknown}}\n";
        }
    }

    $statusScore = $status{critical}
      if ($statusScore > $status{unknown});

    print "QEMU $rstatus{$statusScore} $workingVms / " .
          scalar(@monitoredQemus) . "\n" .
          $reportSummary;

    exit $statusScore;
} else {
    usage();
    exit $status{unknown};
}
