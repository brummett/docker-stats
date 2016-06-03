#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Handle;
use IO::Socket::UNIX;
use HTTP::Request;
use HTTP::Response;

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
    $sock->autoflush(1);

    my $w = AnyEvent->io(
	fh => $sock,
	poll => 'r',
	cb => sub {
	    print "Got response on /events\n";
	    my $lines = 0;
	    while(my $line = $sock->getline()) {
		$lines++;
		chomp $line;
		print "read: >>$line<<\n";
	    }
	    exit unless $lines;
	    if (0) { $sock = undef }
	}
    );

    #my $request = HTTP::Request->new('GET', "/events?since=$last_event_seq");
    #my $request = HTTP::Request->new('GET', "/events");
    #my $request = HTTP::Request->new('GET', "/containers/ps");
print "\n\n\n\n***** sending GET request\n*************************\n\n";
    #$sock->syswrite($request->as_string);
    $sock->syswrite("GET /events HTTP/1.1\n\n");

    return $w;
}
