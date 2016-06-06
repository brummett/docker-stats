#!/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Handle;
use IO::Socket::UNIX;
use HTTP::Request;
use HTTP::Response;
use JSON::XS;
use Data::Dumper;

print "using JSON::XS version $JSON::XS::VERSION\n";

use constant DOCKER_SOCKET_NAME => '/var/run/docker.sock';
my $last_event_seq = 0;

main_loop();

my %CONTAINERS;

sub main_loop {
    my $event_watcher = create_event_watcher();

    my $cv = AnyEvent->condvar();
    my $control_c = AnyEvent->signal(signal => 'INT', cb => sub { print "exiting...\n"; $cv->send() });

    $cv->recv;
    print "done\n";
}

sub _create_watcher_for_docker_socket {
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
    return $handle;
}

sub create_event_watcher {
    my $handle = _create_watcher_for_docker_socket();

    $handle->push_write("GET /events HTTP/1.1\n\n");
#print "\n\n\n********* queued sending GET\n\n\n";

    my $body_reader; $body_reader = sub {
	my($h, $hash) = @_;

#print "Got data: ",Data::Dumper::Dumper($hash);
        $handle->push_read(line => sub { my $len = $_[1]; print "length? line: $len: ",hex($len),"\n" });
	$handle->push_read(json => $body_reader);
        $handle->push_read(line => sub { print "EOL hine: $_[1]\n" });
        $handle->push_read(line => sub { print "blank line: $_[1]\n" });

	if ($hash->{status} eq 'start') {
	    my($id, $job_name, $image) = ($hash->{id}, $hash->{Actor}->{Attributes}->{name}, $hash->{from});
	    $CONTAINERS{$id} = {
		id => $id,
		start_time => $hash->{time},
		job_name => $job_name,
		image => $image,
		status => 'started',
	    };
	    printf("**** Started image %s with job %s\n", $image, $job_name);

	} elsif ($hash->{status} eq 'die') {
	    my($id, $end_time, $exit_code) = ($hash->{id}, $hash->{time}, $hash->{Actor}->{Attributes}->{exitCode});
	    my $container_data = delete $CONTAINERS{$id};
	    unless ($container_data) {
		print "No data for container $id!?\n";
		return;
	    }

	    my $total_time = $end_time - $container_data->{start_time};
	    my $job_name = $container_data->{job_name};
	    my $image = $container_data->{image};

	    printf("**** Docker container %s exited with code %d after %d seconds: LSF job %s\n",
		    $image, $exit_code, $total_time, $job_name);
	}
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
	    $handle->push_read(line => sub { print "throwaway_line: $_[1]\n" });
	    $handle->push_read(json => $body_reader);
	    $handle->push_read(line => sub { print "EOL line: $_[1]\n" });
            $handle->push_read(line => sub { print "blank line: $_[1]\n" });
	}
    };
    $handle->push_read(line => $header_reader);

    return $handle;
}

