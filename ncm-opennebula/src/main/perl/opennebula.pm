# ${license-info}
# ${developer-info}
# ${author-info}


package NCM::Component::opennebula;

use strict;
use NCM::Component;
use base qw(NCM::Component);
use vars qw(@ISA $EC);
use LC::Exception;
use Net::OpenNebula;

use constant AII_OPENNEBULA_CONFIG => "/etc/aii/opennebula.conf";
use constant TEMPLATEPATH => "/usr/share/templates/quattor";

our $EC=LC::Exception::Context->new->will_store_all;

sub make_one 
{
    my ($self, $port, $host, $user, $password) = @_;

    if (! $password ) {
        $main::this_app->error("No RPC ONE password set!");
        return;
    }

    my $one = Net::OpenNebula->new(
        url      => "http://$host:$port/RPC2",
        user     => $user,
        password => $password,
        log => $main::this_app,
        fail_on_rpc_fail => 0,
    );
    return $one;
}

sub new
{
    my $class = shift;
    return bless {}, $class;
}

# Detect and process ONE templates
sub process_template 
{
    my ($self, $config, $tt_name) = @_;
    my $res;
    
    my $tt_rel = "metaconfig/opennebula/$tt_name.tt";
    #my $tree = $config->getElement('/')->getTree();
    my $tpl = Template->new(INCLUDE_PATH => TEMPLATEPATH);
    #if (! $tpl->process($tt_rel, $tree, \$res)) {
    if (! $tpl->process($tt_rel, $config, \$res)) {
            $main::this_app->error("TT processing of $tt_rel failed:", 
                                          $tpl->error());
            return;
    }
    return $res;
}

# Create ONE resources
sub create_something
{
    my ($self, $one, $data, $tt) = @_;
    
    my $template = $self->process_template($data, $tt);
    my $name;
    if ($template =~ m/^NAME\s+=\s+(?:"|')(.*?)(?:"|')\s*$/m) {
        $name = $1;
    } else {
        $self->error("Template NAME not found!");
        return;
    }
    my $method = "create_$tt";
    my $new = $one->$method($template);
}

sub manage_something
{
    my ($self, $one, $resources, $type) = @_;

    $self->info("Removing old ${type}/s...");

    my $method = "get_$type";
    my @exist = $one->$method(qr{^.*$});
    foreach my $t (@existvnet) {
        #$t->delete();
        $self->error("missing implementation ${type} delete");
    }

    $self->info("Creating new ${type}/s...");
    foreach my $t (@$resources) {
        $self->create_something($one, $t, $type);
    }
}


sub manage_vnets
{
    my ($self, $one, $vnets) = @_;
    my $type = "vnet";

    $self->info("Removing old vnets...");

    # Remove the current vnets first..
    # TODO: delete vnet is not available yet
    my @existvnet = $one->get_vnets(qr{^.*$});
    foreach my $t (@existvnet) {
        #$t->delete();
        $self->error('missing implementation $vnet->delete()');
    }

    $self->info("Creating new vnets...");
    foreach my $vnet (@$vnets) {
        $self->create_something($one, $vnet, $type);
    } 
}

sub manage_datastores
{
    my ($self, $one, $datastores) = @_;
    my $type = "datastore";

    $self->info("Removing old datastores...");

    # TODO: delete datastore is not available yet
    my @existdatastore = $one->get_datastores(qr{^.*$});
    foreach my $t (@existdatastore) {
        #$t->delete();
        $self->error('missing implementation $datastore->delete()');
    }

    # TODO: create datastore is not available yet
    $self->info("Creating new datastores...");
    foreach my $datastore (@$datastores) {
        #$self->create_something($one, $datastore, $type);
        $self->error('missing implementation create_datastore()');
    }

}

sub manage_hosts
{
}


# Configure basic ONE resources
sub Configure
{
    my ($self, $config) = @_;

    # Define paths for convenience.
    my $base = "/software/components/opennebula";
    my $tree = $config->getElement($base)->getTree();

    # Connect to ONE RPC
    my $port = $tree->{port};
    my $host = $tree->{host};
    my $user = $tree->{user};
    my $password = $tree->{password};
    
    $main::this_app->info("THIS IS THE HOST: $host");
   
    my $one = $self->make_one($port, $host, $user, $password);

    # Add/remove VNETs
    $self->manage_vnets($one, $tree->{vnets});
    #$self->manage_something($one, $tree->{vnets}, "vnet");

    # Add/remove datastores
    $self->manage_datastores($one, $tree->{datastores_ceph});
    #$self->manage_something($one, $tree->{datastores_ceph}, "datastore");

    # Add/remove KVM hosts
    #$self->manage_hosts($one, $tree->{hosts_kvm});

    # Add/remove users
    #$self->manage_users($one, $config);

    return 1;
}

1;