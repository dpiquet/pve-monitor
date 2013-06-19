pve-monitor is a tool to monitor proxmox virtual environement cluster.

What do we monitor ?

    - nodes
    - storages
    - openvz vms
    - qemu vms

What does API returns ?

==  nodes ==

      "cpu" : 0.00399117390267861,
      "disk" : 1021444096,
      "id" : "node/pyrit",
      "level" : "",
      "maxcpu" : 4,
      "maxdisk" : 101461880832,
      "maxmem" : 8313307136,
      "mem" : 445235200,
      "node" : "pyrit",
      "type" : "node",
      "uptime" : 74536

== storages ==

      "disk" : 6475763712,
      "id" : "storage/pyrit/local",
      "maxdisk" : 858212884480,
      "node" : "pyrit",
      "storage" : "local",
      "type" : "storage"

== openvz ==

      "cpu" : 0,
      "disk" : 0,
      "diskread" : 0,
      "diskwrite" : 0,
      "id" : "openvz/100",
      "maxcpu" : 2,
      "maxdisk" : 21474836480,
      "maxmem" : 2147483648,
      "mem" : 0,
      "name" : "lighttpd.dpiquet.me",
      "netin" : 0,
      "netout" : 0,
      "node" : "pyrit",
      "status" : "stopped",
      "template" : 0,
      "type" : "openvz",
      "uptime" : 0,
      "vmid" : 100

== qemu ==

      "cpu" : 0,
      "disk" : 0,
      "diskread" : 0,
      "diskwrite" : 0,
      "id" : "qemu/103",
      "maxcpu" : 1,
      "maxdisk" : 34359738368,
      "maxmem" : 536870912,
      "mem" : 0,
      "name" : "qemutest",
      "netin" : 0,
      "netout" : 0,
      "node" : "pyrit",
      "status" : "stopped",
      "template" : 0,
      "type" : "qemu",
      "uptime" : 0,
      "vmid" : 103

