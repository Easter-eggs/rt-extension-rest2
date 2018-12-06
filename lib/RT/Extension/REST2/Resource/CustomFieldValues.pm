package RT::Extension::REST2::Resource::CustomFieldValues;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

extends 'RT::Extension::REST2::Resource::Collection';
with 'RT::Extension::REST2::Resource::Collection::QueryByJSON';

use POSIX qw(ceil);

has 'customfield' => (
    is  => 'ro',
    isa => 'RT::CustomField',
);

sub dispatch_rules {
    Path::Dispatcher::Rule::Regex->new(
        regex => qr{^/customfield/(\d+)/values/?$},
        block => sub {
            my ($match, $req) = @_;
            my $cf_id = $match->pos(1);
            my $cf = RT::CustomField->new($req->env->{"rt.current_user"});
            $cf->Load($cf_id);
            my $values = $cf->Values;
            return { customfield => $cf, collection => $values }
        },
    )
}

sub forbidden {
    my $self = shift;
    my $method = $self->request->method;
    if ($method eq 'GET') {
        return !$self->customfield->CurrentUserHasRight('SeeCustomField');
    } else {
        return !($self->customfield->CurrentUserHasRight('AdminCustomField') ||$self->customfield->CurrentUserHasRight('AdminCustomFieldValues'));
    }
}

sub serialize {
    my $self = shift;
    my $collection = $self->collection;
    my $cf = $self->customfield;
    my @results;

    my $per_page = $self->request->param('per_page') || 20;
    if    ($per_page !~ /^\d+$/ ) { $per_page = 20  }
    elsif ($per_page == 0       ) { $per_page = 20  }
    elsif ($per_page > 100      ) { $per_page = 100 }
    $collection->RowsPerPage($per_page);

    my $count_all = $collection->CountAll;
    my $max_page = ceil($count_all / $per_page);

    my $page = $self->request->param('page') || 1;
    if    ($page !~ /^\d+$/  ) { $page = 1 }
    elsif ($page == 0        ) { $page = 1 }
    elsif ($page > $max_page ) { $page = $max_page }
    $self->collection->GotoPage($page - 1);

    while (my $item = $collection->Next) {
        my $result = {
            type => 'customfieldvalue',
            id   => $item->id,
            name   => $item->Name,
            _url => RT::Extension::REST2->base_uri . "/customfield/" . $cf->id . '/value/' . $item->id,
        };
        push @results, $result;
    }

    my %results = (
        count       => scalar(@results) + 0,
        total       => $count_all       + 0,
        per_page    => $per_page        + 0,
        page        => $page            + 0,
        items       => \@results,
    );

    my $uri = $self->request->uri;
    my @query_form = $uri->query_form;
    # find page and if it is set, delete it and it's value.
    for my $i (0..$#query_form) {
        if ($query_form[$i] eq 'page') {
            delete @query_form[$i, $i + 1];
            last;
        }
    }

    $results{pages} = ceil($results{total} / $results{per_page});
    if ($results{page} < $results{pages}) {
        my $page = $results{page} + 1;
        $uri->query_form( @query_form, page => $results{page} + 1 );
        $results{next_page} = $uri->as_string;
    };
    if ($results{page} > 1) {
        $uri->query_form( @query_form, page => $results{page} - 1 );
        $results{prev_page} = $uri->as_string;
    };

    return \%results;
}

__PACKAGE__->meta->make_immutable;

1;
