#${PMpre} NCM::Component::OpenStack::Nova${PMpost}

use parent qw(NCM::Component::OpenStack::Service);

use Readonly;

Readonly our $NOVA_CONF_FILE => "/etc/nova/nova.conf";

=head2 Methods

=over

=item _attrs

Override C<daemons> attribute

=cut

sub _attrs
{
    my $self = shift;

    $self->{daemons} = [
        'openstack-nova-api',
        'openstack-nova-consoleauth',
        'openstack-nova-scheduler',
        'openstack-nova-conductor',
        'openstack-nova-novncproxy',
    ];
    # Nova has different database parameters
    $self->{db_version} = "db version";
    $self->{db_sync} = "db sync";
}

=item post_populate_service_database

Nova post db_sync execution

=cut

sub post_populate_service_database
{
    my ($self) = @_;
    return 1;
}


=pod

=back

=cut

1;