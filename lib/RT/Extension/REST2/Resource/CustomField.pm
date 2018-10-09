package RT::Extension::REST2::Resource::CustomField;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

extends 'RT::Extension::REST2::Resource::Record';
with 'RT::Extension::REST2::Resource::Record::Readable',
        => { -alias => { serialize => '_default_serialize' } },
     'RT::Extension::REST2::Resource::Record::Hypermedia',
     'RT::Extension::REST2::Resource::Record::DeletableByDisabling',
     'RT::Extension::REST2::Resource::Record::Writable';

sub dispatch_rules {
    Path::Dispatcher::Rule::Regex->new(
        regex => qr{^/customfield/?$},
        block => sub { { record_class => 'RT::CustomField' } },
    ),
    Path::Dispatcher::Rule::Regex->new(
        regex => qr{^/customfield/(\d+)/?$},
        block => sub { { record_class => 'RT::CustomField', record_id => shift->pos(1) } },
    )
}

sub serialize {
    my $self = shift;
    my $data = $self->_default_serialize(@_);

    if ($data->{Values}) {
        if ($self->record->BasedOn && defined $self->request->param('category')) {
            my $category = $self->request->param('category') || '';
            @{$data->{Values}} = grep {$_->{category} eq $category} @{$data->{Values}};
        }
        @{$data->{Values}} = map {$_->{name}} @{$data->{Values}};
    }

    return $data;
}

sub forbidden {
    my $self = shift;
    my $method = $self->request->method;
    if ($self->record->id) {
        if ($method eq 'GET') {
            return !$self->record->CurrentUserHasRight('SeeCustomField');
        } else {
            return !($self->record->CurrentUserHasRight('SeeCustomField') && $self->record->CurrentUserHasRight('AdminCustomField'));
        }
    } else {
        return !$self->current_user->HasRight(Right => "AdminCustomField", Object => RT->System);
    }
    return 0;
}

__PACKAGE__->meta->make_immutable;

1;
