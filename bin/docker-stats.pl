#!/usr/bin/env perl

use AnyEvent;
use AnyEvent::HTTP;

main_loop();

sub main_loop {
    my $event_watcher = create_event_watcher();
    my $cv = AnyEvent->condvar();

    my $control_c = AnyEvent->signal(signal => 'INT', cb => sub { $cv->send() });

    $cv->recv;
}

sub create_event_watcher {


}
