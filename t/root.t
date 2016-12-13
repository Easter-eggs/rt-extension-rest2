use strict;
use warnings;
use lib 't/lib';
use RT::Extension::REST2::Test tests => undef;
use JSON;

my $mech = RT::Extension::REST2::Test->mech;

my $rest_base_path = '/REST/2.0';
my $json = JSON->new->utf8;

# Unauthorized without Basic Auth
{
    my $res = $mech->get($rest_base_path);
    is($res->code, 401, 'Unauthorized');
    is($res->header('content-type'), 'application/json; charset=utf-8');
    is($res->header('www-authenticate'), 'Basic realm="example.com REST API"');
    my $content = $json->decode($res->content);
    is($content->{message}, 'Unauthorized');
}

my $auth = RT::Extension::REST2::Test->authorization_header;

# Documentation on Root Path
{
    for my $path ($rest_base_path, "$rest_base_path/") {
        my $res = $mech->get($path, 'Authorization' => $auth);
        is($res->code, 200);
        is($res->header('content-type'), 'text/html; charset=utf-8');

        # this is a temp solution as for main doc
        # TODO: write an end user aimed documentation
        $mech->content_like(qr/RT\-Extension\-REST2/);
        $mech->content_like(qr/NAME/);
        $mech->content_like(qr/INSTALLATION/);
        $mech->content_like(qr/USAGE/);

        $res = $mech->head($path, 'Authorization' => $auth);
        is($res->code, 200);
        is($res->header('content-type'), 'text/html; charset=utf-8');
    }
}

# Allowed Methods
{
    my $res = $mech->post(
        $rest_base_path,
        { param => 'value' },
        'Authorization' => $auth,
    );
    is($res->code, 405);
    is($res->header('allow'), 'GET,HEAD,OPTIONS');
    is($res->header('content-type'), 'application/json; charset=utf-8');
    my $content = $json->decode($res->content);
    is($content->{message}, 'Method Not Allowed');
}

done_testing;