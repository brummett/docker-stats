#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Handle;
use IO::Socket::UNIX;
use HTTP::Request;
use HTTP::Response;
use JSON::XS;

print "using JSON::XS version $JSON::XS::VERSION\n";

use constant DOCKER_SOCKET_NAME => '/var/run/docker.sock';
my $last_event_seq = 0;

main_loop();

sub main_loop {
    my $event_watcher = create_event_watcher();

    my $cv = AnyEvent->condvar();
    my $control_c = AnyEvent->signal(signal => 'INT', cb => sub { print "exiting...\n"; $cv->send() });

    $cv->recv;
    print "done\n";
}

sub create_event_watcher {
    my $sock = IO::Socket::UNIX->new(
                    Type => SOCK_STREAM,
                    Peer => DOCKER_SOCKET_NAME
                ) || die "Can't open docker socket: $!";

    my $handle; $handle = AnyEvent::Handle->new(
	    fh => $sock,
	    on_error => sub {
		my($h, $fatal, $msg) = @_;
		print "Error on docker socket, fatal $fatal, msg: $msg\n";
		$handle->destroy;
	    },
    );

    #my $request = HTTP::Request->new('GET', '/events');
    #$handle->push_write($request->as_string);
    $handle->push_write("GET /events HTTP/1.1\n\n");
    print "\n\n\n********* queued sending GET\n\n\n";

    my $body_reader; $body_reader = sub {
	my($h, $hash) = @_;

	print "Got data: ",Data::Dumper::Dumper($hash);
	$handle->push_read(json => $body_reader);
    };

    my $header_reader; $header_reader = sub {
	my($h, $line) = @_;
	$line =~ s/\r|\n//;
	print "Got header line: $line\n";
	if ($line) {
	    # more headers?
	    $handle->push_read(line => $header_reader);
	} else {
	    # get the body...
print "next is the body data...\n";
	    $handle->push_read(json => $body_reader);
	}
    };
    $handle->push_read(line => $header_reader);

    return $handle;
}

