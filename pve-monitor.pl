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

my $st_ok = 0;
my $st_warn = 1;
my $st_crit = 3;

my %status = (ok => 0, warning => 1, critical => 2, unknown => 3);

my @monitorNodes= (
    {
        server    =>  '192.168.1.1',
        port      =>  '8006',
        username  =>  'monitor',
        password  =>  'd0f3ca',
        realm     =>  'pve',
    },
    {
        server    =>  '192.168.1.254',
        port      =>  '8006',
        username  =>  'monitor',
        password  =>  'd0f3ca',
        realm     =>  'pve',
    },
    {
        server    =>  '192.168.1.253',
        port      =>  '8006',
        username  =>  'monitor',
        password  =>  'd0f3ca',
        realm     =>  'pve',
    },
);

%arguments = (nodes => undef, storages => undef, openvz => undef, qemu => undef);

GetOptions ("nodes"    => \$arguments->{nodes},
            "storages" => \$arguments->{storages},
            "openvz"   => \$arguments->{openvz},
            "qemu"     => \$arguments->{qemu}
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

                 while (<FILE>) {
                     my $objLine = $_;

                     next if ( $objLine =~ m/^#/i );
                     if ( $objLine =~ m/(\w+)\s+(\w+)\s+(\w+)/i ) {
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

                         print "Saving node $name =)\n";

                         $monitoredNodes[scalar(@monitoredNodes)] = (
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
                                 status       => $status->{unknown},
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

                         $monitoredOpenvz[scalar(@monitoredOpenvz)] = (
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
                                 status       => $status->{unknown},
                             },
                         );

                 last;
             }
             case "qemu" {
                 last;
             }
             else { die "Invalid token $1 in configuration file $configurationFile !\n"; }
         }
    }
}

for($a = 0; $a < scalar(@monitorNodes); $a++) {
    $host     = $monitorNodes[$a]->{server};    
    $username = $monitorNodes[$a]->{username};
    $password = $monitorNodes[$a]->{password};
    $realm    = $monitorNodes[$a]->{realm};

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

if (defined $arguments->{node}) {
    my $statusScore = 0;

    my $reportSummary = '';

    foreach my $mnode( @monitoredNodes ) {
        $statusScore += $mnode->{status};
        
        $statusScore += $status->{warning}
          if (($mnode->{curmem} > $mnode->{warn_mem})
          and (defined $mnode->{warn_mem}));

        $statusScore += $status->{critical}
          if (($mnode->{curmem} > $mnode->{crit_mem})
          and (defined $mnode->{critmem}));

        $statusScore += $status->{warning}
          if (($mnode->{curdisk} > $mnode->{warn_disk})
          and (defined $mnode->{warn_disk}));

        $statusScore += $status->{critical}
          if (($mnode->{curdisk} > $mnode->{crit_disk})
          and (defined $mnode->{crit_disk}));

        $statusScore += $status->{warning}
          if (($mnode->{curcpu} > $mnode->{warn_cpu})
          and (defined $mnode->{warn_cpu}));

        $statusScore += $status->{warning}
          if (($mnode->{curcpu} > $mnode->{warn_cpu})
          and (defined $mnode->{warn_cpu}));

        $reportSummary .= "VM $mnode->{name} $mnode->{status} : " .
                          "cpu $mnode->{curcpu}, " . 
                          "mem $mnode->{curmem}, " . 
                          "disk $mnode->{curdisk}\n";
    }

    $statusScore = $status->{critical}
      if ( $statusScore > $status->{unknown});

    print "OPENVZ $status working nodes / " . scalar($monitoredNodes) . "\n" . $reportSummary;
    return $statusScore;
}

if (defined $arguments->{openvz}) {
    foreach my $mopenvz( @monitoredOpenVz ) {
    
    }
}

if (defined $arguments->{storage}) {
    print "not implemented yet";
}

if defined $arguments->{qemu}) {
    print "not implemented yet";
}
