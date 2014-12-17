object template vnet_br100;

include 'metaconfig/opennebula/schema';

bind "/metaconfig/contents/vnet" = opennebula_vnet;

"/metaconfig/module" = "opennebula/vnet";

prefix "/metaconfig/contents/vnet";
"name" = "node.cubone.os";
"type" = "FIXED";
"bridge" = "br100";
"gateway" = "10.141.10.250";
"dns" = "10.141.10.250";
"network_mask" = "255.255.0.0";
