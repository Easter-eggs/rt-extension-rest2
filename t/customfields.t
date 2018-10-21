use strict;
use warnings;
use lib 't/lib';
use RT::Extension::REST2::Test tests => undef;

my $mech = RT::Extension::REST2::Test->mech;
my $auth = RT::Extension::REST2::Test->authorization_header;
my $rest_base_path = '/REST/2.0';
my $user = RT::Extension::REST2::Test->user;

# Right test - create customfield without SeeCustomField nor AdminCustomField
{
    my $payload = {
        Name      => 'Freeform CF',
        Type      => 'Freeform',
        MaxValues => 1,
    };
    my $res = $mech->post_json("$rest_base_path/customfield",
        $payload,
        'Authorization' => $auth,
    );
    is($res->code, 403);
    is($res->message, 'Forbidden');

    my $freeform_cf = RT::CustomField->new(RT->SystemUser);
    my ($ok, $msg) = $freeform_cf->Load('Freeform CF');
    is($freeform_cf->id, undef);
    ok(!$ok);
    is($msg, 'Not found');
}

# Customfield create
{
    $user->PrincipalObj->GrantRight( Right => 'SeeCustomField' );
    $user->PrincipalObj->GrantRight( Right => 'AdminCustomField' );
    my $payload = {
        Name       => 'Freeform CF',
        Type       => 'Freeform',
        LookupType => 'RT::Queue-RT::Ticket',
        MaxValues  => 1,
    };
    my $res = $mech->post_json("$rest_base_path/customfield",
        $payload,
        'Authorization' => $auth,
    );
    is($res->code, 201);

    my $freeform_cf = RT::CustomField->new(RT->SystemUser);
    $freeform_cf->Load('Freeform CF');
    is($freeform_cf->id, 2);
    is($freeform_cf->Description, '');
}

# Right test - search ticket customfields without SeeCustomField
{
    $user->PrincipalObj->RevokeRight( Right => 'SeeCustomField' );

    my $res = $mech->post_json("$rest_base_path/customfields",
        [{field => 'LookupType', value => 'RT::Queue-RT::Ticket'}],
        'Authorization' => $auth,
    );
    is($res->code, 200);

    my $content = $mech->json_response;
    is($content->{total}, 1);
    is($content->{count}, 0);
    is_deeply($content->{items}, []);
}

# Search ticket customfields
{
    $user->PrincipalObj->GrantRight( Right => 'SeeCustomField' );

    my $res = $mech->post_json("$rest_base_path/customfields",
        [{field => 'LookupType', value => 'RT::Queue-RT::Ticket'}],
        'Authorization' => $auth,
    );
    is($res->code, 200);

    my $content = $mech->json_response;
    is($content->{total}, 1);
    is($content->{count}, 1);
    is(scalar(@{$content->{items}}), 1);
    is(scalar(keys %{$content->{items}->[0]}), 3);
    is($content->{items}->[0]->{type}, 'customfield');
    is($content->{items}->[0]->{id}, 2);
    like($content->{items}->[0]->{_url}, qr{$rest_base_path/customfield/2$});
}

# Right test - display customfield without SeeCustomField
{
    $user->PrincipalObj->RevokeRight( Right => 'SeeCustomField' );

    my $res = $mech->get("$rest_base_path/customfield/2",
        'Authorization' => $auth,
    );
    is($res->code, 403);
}

# Display customfield 
{
    $user->PrincipalObj->GrantRight( Right => 'SeeCustomField' );

    my $res = $mech->get("$rest_base_path/customfield/2",
        'Authorization' => $auth,
    );
    is($res->code, 200);
    my $content = $mech->json_response;
    is($content->{id}, 2);
    is($content->{Name}, 'Freeform CF');
    is($content->{Description}, '');
    is($content->{LookupType}, 'RT::Queue-RT::Ticket');
    is($content->{Type}, 'Freeform');
    is($content->{MaxValues}, 1);
    is($content->{Disabled}, 0);

    my @fields = qw(SortOrder Pattern Created Creator LastUpdated LastUpdatedBy);
    push @fields, qw(UniqueValues EntryHint) if RT::Handle::cmp_version($RT::VERSION, '4.4.0') >= 0;
    ok(exists $content->{$_}, "got $_") for @fields;

    my $links = $content->{_hyperlinks};
    is(scalar @$links, 1);
    is($links->[0]{ref}, 'self');
    is($links->[0]{id}, 2);
    is($links->[0]{type}, 'customfield');
    like($links->[0]{_url}, qr{$rest_base_path/customfield/2$});
}

# Right test - update customfield without AdminCustomField
{
    $user->PrincipalObj->RevokeRight( Right => 'AdminCustomField' );

    my $payload = {
        Description  => 'This is a CF for testing REST CRUD on CFs',
    };
    my $res = $mech->put_json("$rest_base_path/customfield/2",
        $payload,
        'Authorization' => $auth,
    );
    is($res->code, 403);
    is($res->message, 'Forbidden');
}

# Update customfield
{
    $user->PrincipalObj->GrantRight( Right => 'AdminCustomField' );

    my $payload = {
        Description  => 'This is a CF for testing REST CRUD on CFs',
    };
    my $res = $mech->put_json("$rest_base_path/customfield/2",
        $payload,
        'Authorization' => $auth,
    );
    is($res->code, 200);

    my $freeform_cf = RT::CustomField->new(RT->SystemUser);
    $freeform_cf->Load('Freeform CF');
    is($freeform_cf->id, 2);
    is($freeform_cf->Description, 'This is a CF for testing REST CRUD on CFs');
}

# Right test - delete customfield without AdminCustomField
{
    $user->PrincipalObj->RevokeRight( Right => 'AdminCustomField' );

    my $res = $mech->delete("$rest_base_path/customfield/2",
        'Authorization' => $auth,
    );
    is($res->code, 403);
    is($res->message, 'Forbidden');

    my $freeform_cf = RT::CustomField->new(RT->SystemUser);
    $freeform_cf->Load('Freeform CF');
    is($freeform_cf->Disabled, 0);
}

# Delete customfield
{
    $user->PrincipalObj->GrantRight( Right => 'AdminCustomField' );

    my $res = $mech->delete("$rest_base_path/customfield/2",
        'Authorization' => $auth,
    );
    is($res->code, 204);

    my $freeform_cf = RT::CustomField->new(RT->SystemUser);
    $freeform_cf->Load('Freeform CF');
    is($freeform_cf->Disabled, 1);
}

my $select_cf = RT::CustomField->new(RT->SystemUser);
$select_cf->Create(Name => 'Select CF', Type => 'Select', MaxValues => 1, Queue => 'General');
$select_cf->AddValue(Name => 'First Value', SortOder => 0);
$select_cf->AddValue(Name => 'Second Value', SortOrder => 1);
$select_cf->AddValue(Name => 'Third Value', SortOrder => 2);
my $select_cf_id = $select_cf->id;
my $select_cf_values = $select_cf->Values->ItemsArrayRef;

my $basedon_cf = RT::CustomField->new(RT->SystemUser);
$basedon_cf->Create(Name => 'SubSelect CF', Type => 'Select', MaxValues => 1, Queue => 'General', BasedOn => $select_cf->id);
$basedon_cf->AddValue(Name => 'With First Value', Category => $select_cf_values->[0]->Name, SortOder => 0);
$basedon_cf->AddValue(Name => 'With No Value', SortOder => 0);
my $basedon_cf_id = $basedon_cf->id;
my $basedon_cf_values = $basedon_cf->Values->ItemsArrayRef;

# Select CustomField display
{
    my $res = $mech->get("$rest_base_path/customfield/$select_cf_id",
        'Authorization' => $auth,
    );
    is($res->code, 200);
    my $content = $mech->json_response;
    is($content->{id}, $select_cf_id);
    is($content->{Name}, $select_cf->Name);
    is($content->{Description}, '');
    is($content->{LookupType}, 'RT::Queue-RT::Ticket');
    is($content->{Type}, 'Select');
    is($content->{MaxValues}, 1);
    is($content->{Disabled}, 0);

    my @fields = qw(SortOrder Pattern Created Creator LastUpdated LastUpdatedBy);
    push @fields, qw(UniqueValues EntryHint) if RT::Handle::cmp_version($RT::VERSION, '4.4.0') >= 0;
    ok(exists $content->{$_}, "got $_") for @fields;

    my $links = $content->{_hyperlinks};
    is(scalar @$links, 2);
    is($links->[0]{ref}, 'self');
    is($links->[0]{id}, $select_cf_id);
    is($links->[0]{type}, 'customfield');
    like($links->[0]{_url}, qr{$rest_base_path/customfield/$select_cf_id$});
    is($links->[1]{ref}, 'customfieldvalues');
    like($links->[1]{_url}, qr{$rest_base_path/customfield/$select_cf_id/values$});

    my $values = $content->{Values};
    is_deeply($values, ['First Value', 'Second Value', 'Third Value']);
}

# BasedOn CustomField display
{
    my $res = $mech->get("$rest_base_path/customfield/$basedon_cf_id",
        'Authorization' => $auth,
    );
    is($res->code, 200);
    my $content = $mech->json_response;
    is($content->{id}, $basedon_cf_id);
    is($content->{Name}, $basedon_cf->Name);
    is($content->{Description}, '');
    is($content->{LookupType}, 'RT::Queue-RT::Ticket');
    is($content->{Type}, 'Select');
    is($content->{MaxValues}, 1);
    is($content->{Disabled}, 0);

    my @fields = qw(SortOrder Pattern Created Creator LastUpdated LastUpdatedBy);
    push @fields, qw(UniqueValues EntryHint) if RT::Handle::cmp_version($RT::VERSION, '4.4.0') >= 0;
    ok(exists $content->{$_}, "got $_") for @fields;

    my $links = $content->{_hyperlinks};
    is(scalar @$links, 2);
    is($links->[0]{ref}, 'self');
    is($links->[0]{id}, $basedon_cf_id);
    is($links->[0]{type}, 'customfield');
    like($links->[0]{_url}, qr{$rest_base_path/customfield/$basedon_cf_id$});
    is($links->[1]{ref}, 'customfieldvalues');
    like($links->[1]{_url}, qr{$rest_base_path/customfield/$basedon_cf_id/values$});

    my $values = $content->{Values};
    is_deeply($values, ['With First Value', 'With No Value']);
}

# BasedOn CustomField display with category filter
{
    my $res = $mech->get("$rest_base_path/customfield/$basedon_cf_id?category=First%20Value",
        'Authorization' => $auth,
    );
    is($res->code, 200);
    my $content = $mech->json_response;
    is($content->{id}, $basedon_cf_id);
    is($content->{Name}, $basedon_cf->Name);
    is($content->{Description}, '');
    is($content->{LookupType}, 'RT::Queue-RT::Ticket');
    is($content->{Type}, 'Select');
    is($content->{MaxValues}, 1);
    is($content->{Disabled}, 0);

    my @fields = qw(SortOrder Pattern Created Creator LastUpdated LastUpdatedBy);
    push @fields, qw(UniqueValues EntryHint) if RT::Handle::cmp_version($RT::VERSION, '4.4.0') >= 0;
    ok(exists $content->{$_}, "got $_") for @fields;

    my $links = $content->{_hyperlinks};
    is(scalar @$links, 2);
    is($links->[0]{ref}, 'self');
    is($links->[0]{id}, $basedon_cf_id);
    is($links->[0]{type}, 'customfield');
    like($links->[0]{_url}, qr{$rest_base_path/customfield/$basedon_cf_id$});
    is($links->[1]{ref}, 'customfieldvalues');
    like($links->[1]{_url}, qr{$rest_base_path/customfield/$basedon_cf_id/values$});

    my $values = $content->{Values};
    is_deeply($values, ['With First Value']);
}

# BasedOn CustomField display with null category filter
{
    my $res = $mech->get("$rest_base_path/customfield/$basedon_cf_id?category=",
        'Authorization' => $auth,
    );
    is($res->code, 200);
    my $content = $mech->json_response;
    is($content->{id}, $basedon_cf_id);
    is($content->{Name}, $basedon_cf->Name);
    is($content->{Description}, '');
    is($content->{LookupType}, 'RT::Queue-RT::Ticket');
    is($content->{Type}, 'Select');
    is($content->{MaxValues}, 1);
    is($content->{Disabled}, 0);

    my @fields = qw(SortOrder Pattern Created Creator LastUpdated LastUpdatedBy);
    push @fields, qw(UniqueValues EntryHint) if RT::Handle::cmp_version($RT::VERSION, '4.4.0') >= 0;
    ok(exists $content->{$_}, "got $_") for @fields;

    my $links = $content->{_hyperlinks};
    is(scalar @$links, 2);
    is($links->[0]{ref}, 'self');
    is($links->[0]{id}, $basedon_cf_id);
    is($links->[0]{type}, 'customfield');
    like($links->[0]{_url}, qr{$rest_base_path/customfield/$basedon_cf_id$});
    is($links->[1]{ref}, 'customfieldvalues');
    like($links->[1]{_url}, qr{$rest_base_path/customfield/$basedon_cf_id/values$});

    my $values = $content->{Values};
    is_deeply($values, ['With No Value']);
}

my $queue = RT::Queue->new(RT->SystemUser);
$queue->Load('General');
my $queue_id = $queue->id;

my $attached_single_cf = RT::CustomField->new(RT->SystemUser);
$attached_single_cf->Create(LookupType => 'RT::Queue-RT::Ticket', Name => 'Test queue CF1', Type => 'Freeform', MaxValues => 1, Queue => 'General');
my $attached_single_cf_id = $attached_single_cf->id;

my $attached_multiple_cf = RT::CustomField->new(RT->SystemUser);
$attached_multiple_cf->Create(LookupType => 'RT::Queue-RT::Ticket', Name => 'Test queue CF2', Type => 'Freeform', MaxValues => 0, Queue => 'General');
my $attached_multiple_cf_id = $attached_multiple_cf->id;

my $detached_cf = RT::CustomField->new(RT->SystemUser);
$detached_cf->Create(LookupType => 'RT::Queue-RT::Ticket', Name => 'Test queue CF3', Type => 'Freeform', MaxValues => 1);
my $detached_cf_id = $detached_cf->id;

my $queue_cf = RT::CustomField->new(RT->SystemUser);
$queue_cf->Create(LookupType => 'RT::Queue', Name => 'Test queue CF4', Type => 'Freeform', MaxValues => 1);
$queue_cf->AddToObject($queue);
my $queue_cf_id = $queue_cf->id;

# All tickets single customfields attached to queue 'General'
{
    my $res = $mech->post_json("$rest_base_path/queue/$queue_id/customfields",
        [
            {field => 'LookupType', value => 'RT::Queue-RT::Ticket'},
            {field => 'MaxValues', value => 1},
            {field => 'Name', operator => 'STARTSWITH', value => 'Test queue CF'},
        ],
        'Authorization' => $auth,
    );
    is($res->code, 200);

    my $content = $mech->json_response;
    is($content->{total}, 1);
    is($content->{count}, 1);
    is(scalar @{$content->{items}}, 1);
    is($content->{items}->[0]->{id}, $attached_single_cf_id);
}

# All single customfields attached to queue 'General'
{
    my $res = $mech->post_json("$rest_base_path/queue/$queue_id/customfields",
        [
            {field => 'MaxValues', value => 1},
            {field => 'Name', operator => 'STARTSWITH', value => 'Test queue CF'},
        ],
        'Authorization' => $auth,
    );
    is($res->code, 200);

    my $content = $mech->json_response;
    is($content->{total}, 2);
    is($content->{count}, 2);
    is(scalar @{$content->{items}}, 2);
    my @ids = sort map {$_->{id}} @{$content->{items}};
    is_deeply(\@ids, [$attached_single_cf_id, $queue_cf_id]);
}

done_testing;
