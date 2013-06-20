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

# Read the configuration file
open FILE, "<", "$configurationFile" or die $!;
while ( <FILE> ) {
    my $line = $_;

    # Skip commented lines (starting with #)
    next if $line =~ m/^#/i;

    # we got an object definition here !
    if ( $line =~ m/(\w+)\s+(\w+)\s+\{/i ) {
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

                         print "Saving node $name =)\n";

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
                             },
                         );
                              
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

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^#/i );
                     if ( $objLine =~ m/(\w+)\s+(\w+)\s+(\w+)/i ) {
                         switch ($1) {
                             case "cpu" {
                                 $warnCpu = $2;
                                 $critCpu = $4;
                             }
                             case "mem" {
                                 $warnMem = $2;
                                 $critMem = $4;
                             }
                             case "disk" {
                                 $warnDisk = $2;
                                 $critDisk = $4;
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
                             },
                         );
                     }
                 }

                 last;
             }
             case "qemu" {
                 last;
             }
             else { die "Invalid token $1 in configuration file $configurationFile !\n"; }
         }
    }
}

close(FILE);

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
                $mnode->{alive}   = 1; # not verified...
                $mnode->{status}  = $status{ok};
                $mnode->{curmem}  = ( $item->{mem} / $item->{maxmem} );
                $mnode->{curdisk} = ( $item->{disk} / $item->{maxdisk} );
                $mnode->{curcpu}  = ( $item->{cpu} / $item->{maxcpu} );
            }
        }
        case "storage" {
            next;
        }
        case "openvz" {
            next;
        }
        case "qemu" {
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
        
        $statusScore += $status{warning}
          if ((defined $mnode->{warn_mem})
          and ($mnode->{curmem} > $mnode->{warn_mem}));

        $statusScore += $status{critical}
          if ((defined $mnode->{critmem})
          and ($mnode->{curmem} > $mnode->{crit_mem}));

        $statusScore += $status{warning}
          if ((defined $mnode->{warn_disk})
          and ($mnode->{curdisk} > $mnode->{warn_disk}));

        $statusScore += $status{critical}
          if ((defined $mnode->{crit_disk})
          and ($mnode->{curdisk} > $mnode->{crit_disk}));

        $statusScore += $status{warning}
          if ((defined $mnode->{warn_cpu})
          and ($mnode->{curcpu} > $mnode->{warn_cpu}));

        $statusScore += $status{warning}
          if ((defined $mnode->{warn_cpu})
          and ($mnode->{curcpu} > $mnode->{warn_cpu}));

        if ($mnode->{status} ne $status{unknown}) {
            $reportSummary .= "VM $mnode->{name} $rstatus{$mnode->{status}} : " .
                              "cpu $mnode->{curcpu}, " . 
                              "mem $mnode->{curmem}, " . 
                              "disk $mnode->{curdisk}\n";
        }
        else { $reportSummary .= "VM $mnode->{name} is in status $status{unknown}\n"; }
    }

    $statusScore = $status{critical}
      if ( $statusScore > $status{unknown});

    print "OPENVZ $statusScore  $workingNodes / " . scalar(@monitoredNodes) . "\n" . $reportSummary;
    exit $statusScore;
}

if (defined $arguments{openvz}) {
    foreach my $mopenvz( @monitoredOpenvz ) {
        print "not yet implemented";
    }
}

if (defined $arguments{storages}) {
    print "not implemented yet";
}

if (defined $arguments{qemu}) {
    print "not implemented yet";
}
