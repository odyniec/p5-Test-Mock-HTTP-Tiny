package Test::Mock::HTTP::Tiny;

use strict;
use warnings;

# ABSTRACT: Record and replay HTTP requests/responses with HTTP::Tiny

# VERSION

use Data::Dumper;
use HTTP::Tiny;
use Test::Deep::NoTest;
use URI::Escape;

=head1 SYNOPSIS

Capture HTTP data:

    use HTTP::Tiny;
    use Test::Mock::HTTP::Tiny;

    my $http = HTTP::Tiny->new;
    my $resp = $http->get('http://www.cpan.org/');

    print STDERR Test::Mock::HTTP::Tiny->captured_data_dump;

Replay captured data:

    Test::Mock::HTTP::Tiny->set_mocked_data([
        {
            url      => 'http://www.cpan.org/',
            method   => 'GET',
            args     => { ... },
            response => { ... },
        }
    ]);

    $resp = $http->get('http://www.cpan.org/');

=head1 DESCRIPTION

(TBA)

=cut

my $captured_data = [];
my $mocked_data   = [];

=head1 METHODS

=head2 mocked_data

=cut

sub mocked_data {
    return $mocked_data;
}

=head2 set_mocked_data

=cut

sub set_mocked_data {
    my ($class, $new_mocked_data) = @_;

    if (ref($new_mocked_data) eq 'ARRAY') {
        # An arrayref of items was provided
        $mocked_data = [ @$new_mocked_data ];
    }
    elsif (ref($new_mocked_data) eq 'HASH') {
        # A single item was provided
        $mocked_data = [ { %$new_mocked_data } ];
    }
    else {
        # TODO: error
    }
}

=head2 append_mocked_data

=cut

sub append_mocked_data {
    my ($class, $new_mocked_data) = @_;

    if (ref($new_mocked_data) eq 'ARRAY') {
        # Multiple items are being appended
        push @$mocked_data, @$new_mocked_data;
    }
    elsif (ref($new_mocked_data) eq 'HASH') {
        # Single item is being appended
        push @$mocked_data, { %$new_mocked_data };
    }
    else {
        # TODO: error
    }
}

=head2 clear_mocked_data

=cut

sub clear_mocked_data {
    $mocked_data = [];
}

=head2 captured_data

=cut

sub captured_data {
    return $captured_data;
}

=head2 captured_data_dump

=cut

sub captured_data_dump {
    local $Data::Dumper::Deepcopy = 1;
    return Dumper $captured_data;
}

=head2 clear_captured_data

=cut

sub clear_captured_data {
    $captured_data = [];
}

{
    ## no critic
    no strict 'refs';
    no warnings 'redefine';
    my $_HTTP_Tiny__request = \&HTTP::Tiny::_request;
    *{"HTTP::Tiny::_request"} = sub {
        my ($self, $method, $url, $args) = @_;

        my $normalized_args = { %$args };

        if (exists $args->{headers}{'content-type'} &&
            $args->{headers}{'content-type'} eq
                'application/x-www-form-urlencoded')
        {
            # Unescape form data
            $normalized_args->{content} = {};

            for my $param (split(/&/, $args->{content})) {
                my ($name, $value) =
                    map { uri_unescape($_) } split(/=/, $param, 2);
                $normalized_args->{content}{$name} = $value;
            }
        }

        for my $i (0 .. $#{$mocked_data}) {
            my $mock_req = $mocked_data->[$i];

            next if !eq_deeply(
                [ $mock_req->{method}, $mock_req->{url}, $mock_req->{args} ],
                [ $method, $url, $normalized_args ]
            );

            # Found a matching request in mocked data
            $mock_req = { %$mock_req };

            # Remove the request from mocked data so that it's not used again
            splice(@$mocked_data, $i, 1);

            # Return the corresponding response
            return $mock_req->{response};
        }

        # No matching request found -- call the actual HTTP::Tiny request method
        my $response = &$_HTTP_Tiny__request($self, $method, $url, $args);

        # Save the request/response in captured data
        push @$captured_data, {
            method   => $method,
            url      => $url,
            args     => $normalized_args,
            response => $response,
        };
    
        return $response;
    };
}

1;
