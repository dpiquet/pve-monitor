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

my $debug = 0;
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
);

GetOptions ("nodes"    => \$arguments{nodes},
            "storages" => \$arguments{storages},
            "openvz"   => \$arguments{openvz},
            "qemu"     => \$arguments{qemu},
);

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
open FILE, "<", "$configurationFile" or die $!;
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
                     if ( $objLine =~ m/([\w\.]+)\s+([\w\.]+)(\s+([\w+\.]))?/i ) {

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
                             else { die "Invalid token $1 in $name definition !\n"; }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         die "Invalid configuration !" unless defined $name;

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
                 last;
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
                             else { die "Invalid token $1 in $name definition !\n"; }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         die "Invalid configuration !" unless defined $name;

                         print "Saving openvz $name =)\n";

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
                             else { die "Invalid token $1 in $name definition !\n"; }
                         }
                     }
                     elsif ( $objLine =~ m/\}/i ) {
                         # check object requirements are met, save it, break
                         die "Invalid configuration !" unless defined $name;

                         print "Saving qemu $name =)\n";

                         $monitoredQemus[scalar(@monitoredQemus)] = ({
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
                                 status       => $status{unknown},
                                 uptime       => undef,
                             },
                         );
                         $readingObject = 0;
                         last;
                     }
                 }
             }
             else { die "Invalid token $1 in configuration file $configurationFile !\n"; }
         }
    }
}

close(FILE);

die "Invalid configuration !" unless ($readingObject eq 0);

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

die "Could not connect to any server !" unless $connected;

# list all ressources of the cluster
my $objects = $pve->get('/cluster/resources');

print "Found " . scalar(@$objects) . " objects:\n";

# loop the objects to compare our definitions with the current state of the cluster
foreach my $item( @$objects ) { 
    switch ($item->{type}) {
        case "node" {
            # loop the node array to see if that one is monitored
            foreach my $mnode( @monitoredNodes ) {
                next unless ($item->{node} eq $mnode->{name});
                $mnode->{status}  = $status{ok};
                $mnode->{curmem}  = sprintf("%.2f", (( $item->{mem} / $item->{maxmem} ) * 100));
                $mnode->{curdisk} = sprintf("%.2f", (( $item->{disk} / $item->{maxdisk} ) * 100));
                $mnode->{curcpu}  = sprintf("%.2f", (( $item->{cpu} / $item->{maxcpu} ) * 100));
            }
        }
        case "storage" {
            next;
        }
        case "openvz" {
            foreach my $mopenvz( @monitoredOpenvz ) {
                next unless ($item->{name} eq $mopenvz->{name});

                $mopenvz->{status} = $status{critical}
                  if $item->{status} eq 'stopped';

                $mopenvz->{status} = $status{warning}
                  if $item->{status} eq 'suspend';

                $mopenvz->{status} = $status{ok}
                  if $item->{status} eq 'running';

                $mopenvz->{curmem}  = sprintf("%.2f", (( $item->{mem} / $item->{maxmem} ) * 100));
                $mopenvz->{curdisk} = sprintf("%.2f", (( $item->{disk} / $item->{maxdisk} ) * 100));
                $mopenvz->{curcpu}  = sprintf("%.2f", (( $item->{cpu} / $item->{maxcpu} ) * 100));
            }
            next;
        }
        case "qemu" {
            foreach my $mqemu( @monitoredQemus ) {
                next unless ($item->{name} eq $mqemu->{name});

                $mqemu->{status} = $status{critical}
                  if $item->{status} eq 'stopped';

                $mqemu->{status} = $status{warning}
                  if $item->{status} eq 'suspend';

                $mqemu->{status} = $status{ok}
                  if $item->{status} eq 'running';

                $mqemu->{curmem}  = sprintf("%.2f", (( $item->{mem} / $item->{maxmem} ) * 100));
                $mqemu->{curdisk} = sprintf("%.2f", (( $item->{disk} / $item->{maxdisk} ) * 100));
                $mqemu->{curcpu}  = sprintf("%.2f", (( $item->{cpu} / $item->{maxcpu} ) * 100));
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
            $statusScore += $status{warning}
              if ($mnode->{curmem} > $mnode->{warn_mem});

            $statusScore += $status{critical}
              if ($mnode->{curmem} > $mnode->{crit_mem});

            $statusScore += $status{warning}
              if ($mnode->{curdisk} > $mnode->{warn_disk});

            $statusScore += $status{critical}
              if ($mnode->{curdisk} > $mnode->{crit_disk});

            $statusScore += $status{warning}
              if ($mnode->{curcpu} > $mnode->{warn_cpu});

            $statusScore += $status{warning}
              if ($mnode->{curcpu} > $mnode->{warn_cpu});

            $reportSummary .= "NODE $mnode->{name} $rstatus{$mnode->{status}} : " .
                              "cpu $mnode->{curcpu}%, " . 
                              "mem $mnode->{curmem}%, " . 
                              "disk $mnode->{curdisk}%\n";

            $workingNodes++;
        }
        else {
            $reportSummary .= "NODE $mnode->{name} is in status $rstatus{$status{unknown}}\n";
        }
    }

    $statusScore = $status{critical}
      if ( $statusScore > $status{unknown});

    print "NODES $rstatus{$statusScore}  $workingNodes / " .
          scalar(@monitoredNodes) . "\n" . $reportSummary;

    exit $statusScore;
}

if (defined $arguments{openvz}) {
    my $statusScore = 0;
    my $workingVms = 0;

    my $reportSummary = '';

    foreach my $mopenvz( @monitoredOpenvz ) {
        if ($mopenvz->{status} ne $status{unknown}) {
            $statusScore += $status{warning}
              if ($mopenvz->{curmem} > $mopenvz->{warn_mem});

            $statusScore += $status{critical}
              if $mopenvz->{curmem} > $mopenvz->{crit_mem};

            $statusScore += $status{warning}
              if $mopenvz->{curdisk} > $mopenvz->{warn_disk};

            $statusScore += $status{critical}
              if $mopenvz->{curdisk} > $mopenvz->{crit_disk};

            $statusScore += $status{warning}
              if $mopenvz->{curcpu} > $mopenvz->{warn_cpu};

            $statusScore += $status{critical}
              if $mopenvz->{curcpu} > $mopenvz->{crit_cpu};

            $reportSummary .= "OPENVZ $mopenvz->{name} $rstatus{$mopenvz->{status}} : " .
                              "cpu $mopenvz->{curcpu}%, " .
                              "mem $mopenvz->{curmem}%, " .
                              "disk $mopenvz->{curdisk}%\n";

            $workingVms++;
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
}

if (defined $arguments{storages}) {
    print "not implemented yet";
}

if (defined $arguments{qemu}) {
    my $statusScore = 0;
    my $workingVms = 0;

    my $reportSummary = '';

    foreach my $mqemu( @monitoredQemus ) {
        if ($mqemu->{status} ne $status{unknown}) {
            $statusScore += $status{warning}
              if ($mqemu->{curmem} > $mqemu->{warn_mem});

            $statusScore += $status{critical}
              if $mqemu->{curmem} > $mqemu->{crit_mem};

            $statusScore += $status{warning}
              if $mqemu->{curdisk} > $mqemu->{warn_disk};

            $statusScore += $status{critical}
              if $mqemu->{curdisk} > $mqemu->{crit_disk};

            $statusScore += $status{warning}
              if $mqemu->{curcpu} > $mqemu->{warn_cpu};

            $statusScore += $status{critical}
              if $mqemu->{curcpu} > $mqemu->{crit_cpu};

            $reportSummary .= "OPENVZ $mqemu->{name} $rstatus{$mqemu->{status}} : " .
                              "cpu $mqemu->{curcpu}%, " .
                              "mem $mqemu->{curmem}%, " .
                              "disk $mqemu->{curdisk}%\n";

            $workingVms++;
        }
        else {
            $reportSummary .= "QEMU $mqemu->{name} is in status $rstatus{$status{unknown}}\n";
        }
    }

    $statusScore = $status{critical}
      if ($statusScore > 3);

    print "QEMU $rstatus{$statusScore} $workingVms / " .
          scalar(@monitoredQemus) . "\n" .
          $reportSummary;

    exit $statusScore;
}
