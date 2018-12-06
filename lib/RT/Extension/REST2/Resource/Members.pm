package RT::Extension::REST2::Resource::Members;
use strict;
use warnings;

use Moose;
use namespace::autoclean;
use POSIX qw(ceil);

extends 'RT::Extension::REST2::Resource::Collection';
with 'RT::Extension::REST2::Resource::Role::RequestBodyIsJSON' =>
  {type => 'ARRAY'};

has 'group' => (
    is  => 'ro',
);

sub dispatch_rules {
    Path::Dispatcher::Rule::Regex->new(
        regex => qr{^/group/(\d+)/(deep|group|user)?members/?$},
        block => sub {
            my ($match, $req) = @_;
            my $group_id = $match->pos(1);
            my $type = $match->pos(2) || '';
            my $group = RT::Group->new($req->env->{"rt.current_user"});
            $group->Load($group_id);
            my $collection;

            if ($type eq 'deep') {
                $collection = $group->DeepMembersObj;
            } elsif ($type eq 'group') {
                $collection = $group->GroupMembersObj(Recursively => $req->parameters->{recursively} // 1);
                $collection->ItemsArrayRef;
            } elsif ($type eq 'user') {
                $collection = $group->UserMembersObj(Recursively => $req->parameters->{recursively} // 1);
            } else {
                $collection = $group->MembersObj;
            }

            return {group => $group, collection => $collection};
        },
    ),
    Path::Dispatcher::Rule::Regex->new(
        regex => qr{^/group/(\d+)/member/(\d+)/?$},
        block => sub {
            my ($match, $req) = @_;
            my $group_id = $match->pos(1);
            my $member_id = $match->pos(2) || '';
            my $group = RT::Group->new($req->env->{"rt.current_user"});
            $group->Load($group_id);
            my $collection = $group->MembersObj;
            $collection->Limit(FIELD => 'MemberId', VALUE => $member_id);
            return {group => $group, collection => $collection};
        },
    ),
}

sub forbidden {
    my $self = shift;
    return 0 unless $self->group->id;
    return !$self->group->CurrentUserHasRight('AdminGroupMembership');
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
        my ($id, $class);
        if (ref $item eq 'RT::GroupMember' || ref $item eq 'RT::CachedGroupMember') {
            my $principal = $item->MemberObj;
            $class = $principal->IsGroup ? 'group' : 'user';
            $id = $principal->id;
        } elsif (ref $item eq 'RT::Group') {
            $class = 'group';
            $id = $item->id;
        } elsif (ref $item eq 'RT::User') {
            $class = 'user';
            $id = $item->id;
        }
        else {
            next;
        }

        my $result = {
            type => $class,
            id   => $id,
            _url => RT::Extension::REST2->base_uri . "/$class/$id",
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
    while (my $group_member = $collection->Next) {
        $RT::Logger->info('Delete ' . ($group_member->MemberObj->IsGroup ? 'group' : 'user') . ' ' . $group_member->MemberId . ' from group '.$group_member->GroupId);
        $group_member->GroupObj->Object->DeleteMember($group_member->MemberId);
    }
    return 1;
}

sub from_json {
    my $self   = shift;
    my $params = JSON::decode_json($self->request->content);
    my $group = $self->group;

    my $method = $self->request->method;
    my @results;
    if ($method eq 'PUT') {
        for my $param (@$params) {
            if ($param =~ /^\d+$/) {
                push @results, $group->AddMember($param);
            } else {
                push @results, [0, 'You should provide principal id for each member to add'];
            }
        }
    }
    $self->response->body(JSON::encode_json(\@results));
    return;
}

__PACKAGE__->meta->make_immutable;

1;
