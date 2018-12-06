package RT::Extension::REST2::Resource::UserGroups;
use strict;
use warnings;

use Moose;
use namespace::autoclean;
use POSIX qw(ceil);

extends 'RT::Extension::REST2::Resource::Collection';
with 'RT::Extension::REST2::Resource::Role::RequestBodyIsJSON' =>
  {type => 'ARRAY'};

has 'user' => (
    is  => 'ro',
    isa => 'RT::User',
);

sub dispatch_rules {
    Path::Dispatcher::Rule::Regex->new(
        regex => qr{^/user/([^/]+)/groups/?$},
        block => sub {
            my ($match, $req) = @_;
            my $user_id = $match->pos(1);
            my $user = RT::User->new($req->env->{"rt.current_user"});
            $user->Load($user_id);

            return {user => $user, collection => $user->OwnGroups};
        },
    ),
    Path::Dispatcher::Rule::Regex->new(
        regex => qr{^/user/([^/]+)/group/(\d+)/?$},
        block => sub {
            my ($match, $req) = @_;
            my $user_id = $match->pos(1);
            my $group_id = $match->pos(2) || '';
            my $user = RT::User->new($req->env->{"rt.current_user"});
            $user->Load($user_id);
            my $collection = $user->OwnGroups(Recursively => 0);
            $collection->Limit(FIELD => 'id', VALUE => $group_id);
            return {user => $user, collection => $collection};
        },
    ),
}

sub forbidden {
    my $self = shift;
    return 0 if
        ($self->current_user->HasRight(
            Right  => "ModifyOwnMembership",
            Object => RT->System,
        ) && $self->current_user->id == $self->user->id) ||
        $self->current_user->HasRight(
            Right  => 'AdminGroupMembership',
            Object => RT->System);
    return 1;
}

sub serialize {
    my $self = shift;
    my $collection = $self->collection;
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
            type => 'group',
            id   => $item->id,
            _url => RT::Extension::REST2->base_uri . "/group/" . $item->id,
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

sub allowed_methods {
    my @ok = ('GET', 'HEAD', 'DELETE', 'PUT');
    return \@ok;
}

sub content_types_accepted {[{'application/json' => 'from_json'}]}

sub delete_resource {
    my $self = shift;
    my $collection = $self->collection;
    while (my $group = $collection->Next) {
        $RT::Logger->info('Delete user ' . $self->user->Name . ' from group '.$group->id);
        $group->DeleteMember($self->user->id);
    }
    return 1;
}

sub from_json {
    my $self   = shift;
    my $params = JSON::decode_json($self->request->content);
    my $user = $self->user;

    my $method = $self->request->method;
    my @results;
    if ($method eq 'PUT') {
        for my $param (@$params) {
            if ($param =~ /^\d+$/) {
                my $group = RT::Group->new($self->request->env->{"rt.current_user"});
                $group->Load($param);
                push @results, $group->AddMember($user->id);
            } else {
                push @results, [0, 'You should provide group id for each group user should be added'];
            }
        }
    }
    $self->response->body(JSON::encode_json(\@results));
    return;
}

__PACKAGE__->meta->make_immutable;

1;
