#!/usr/bin/perl

#####################################################
#
#    Proxmox VE cluster monitoring tool
#
#####################################################
#
#   (c) Damien PIQUET  damien.piquet@iutbeziers.fr || piqudam@gmail.com
#
#   Requires Net::Proxmox::VE librairy: git://github.com/dpiquet/proxmox-ve-api-perl.git
#

use strict;
use warnings;

use lib './lib';
use Net::Proxmox::VE;
use Data::Dumper;
use Getopt::Long;

my $debug = 1;
my $timeout = 5;

my @nodes= (
    {
        server    =>  'host1',
        port      =>  '8006',
        username  =>  'user',
        password  =>  'pass',
        realm     =>  'pam',
    },
    {
        server    =>  'host2',
        port      =>  '8006',
        username  =>  'user',
        password  =>  'pass',
        realm     =>  'pve',
    },
    {
        server    =>  'host3',
        port      =>  '8006',
        username  =>  'user',
        password  =>  'pass',
        realm     =>  'pve',
    },
);

my $connected = 0;
my $host = undef;
my $username = undef;
my $password = undef;
my $realm = undef;
my $pve;

for($a = 0; $a < @nodes; $a++) {
    $host = $nodes[$a]->{server};    
    $username = $nodes[$a]->{username};
    $password = $nodes[$a]->{password};
    $realm = $nodes[$a]->{realm};

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
my $nodes = $pve->get('/cluster/resources');

print "Found " .  @$nodes . " nodes:\n";

foreach my $item( @$nodes ) { 
    # fields are in $item->{Year}, $item->{Quarter}, etc.
    print "id: " . $item->{id} . "\n"; 
    print "type: " . $item->{type} . "\n";
}
