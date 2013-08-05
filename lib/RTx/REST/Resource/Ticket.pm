package RTx::REST::Resource::Ticket;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

extends 'RTx::REST::Resource';
with 'RTx::REST::Resource::Role::Record';
with 'RTx::REST::Resource::Role::Record::Deletable';

sub forbidden {
    my $self = shift;
    return 0 if not $self->record->id;
    return 0 if $self->record->CurrentUserHasRight("ShowTicket");
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;
