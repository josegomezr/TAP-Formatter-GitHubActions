package Test2::Formatter::YAMLEnhancedTAP;

use strict;
use warnings;
use TAP::Parser::YAMLish::Writer;
use base 'Test2::Formatter::TAP';

my $yw = TAP::Parser::YAMLish::Writer->new;
# my $ypp = YAML::PP->new(
#     footer = 1,
# );
sub write2 {
    my ($self, $event, $num, $facet_data) = @_;
    # Facet may be passed explicitly
    $self->SUPER::write($event, $num, $facet_data);

    $facet_data ||= $event->facet_data;
    my $frame = $facet_data->{trace}{frame};
    my (undef, $filename, $lineno, $caller_class) = @{$frame};

    my $info = $facet_data->{info} ? $facet_data->{info}[0] : undef;
    
    # Ignore framework events, we care about what xt,t/ raises.
    return unless $filename =~ m/^(t|xt)/;
    # Ignore passes
    return if $event->isa('Test2::Event::Pass');
    # Ignore OK's that passed
    return if $event->isa('Test2::Event::Ok') && $event->{pass};
    # Ignore "Subtest"
    return if $event->isa('Test2::Event::Plan') || $caller_class eq 'Test::More::subtest';

    my $nesting = $facet_data->{trace}->{nested} || 0;
    my $indent = ('  ') x (1 + $nesting);
    
    my $yaml = "";
    $yw->write({
        at => {
            filename => $filename,
            line => $lineno
        },
        message => $info->{details} // 'failed assertion'
    }, \$yaml);

    $yaml =~ s/^/$indent/mg;
    print "$yaml";
}

sub _yamilify_message {
    my ($self, $frame, $event, $message) = @_;
    my (undef, $filename, $lineno, $caller_class) = @{$frame};

    my $yaml = "";
    # Cleanup comments
    $message =~ s/#\s+//gm;
    # Cleanup extra newlines
    chomp($message);

    # Build the YAML.
    # Sidenote: it doesn't like YAML::PP for whatever reason 🤷
    $yw->write({
        at => {
            filename => $filename,
            line => $lineno
        },
        emitter => $caller_class,
        message => $message
    }, \$yaml);

    # indent two spaces for the TAP parser.
    $yaml =~ s/^/  /mg;
    # add an extra newline for readability
    $yaml .= "\n";
    return $yaml;
}

sub write {
    my ($self, $e, $num, $f) = @_;
    # The most common case, a pass event with no amnesty and a normal name.
    return if $self->print_optimal_pass($e, $num);

    $f ||= $e->facet_data;
    my $frame = $f->{trace}{frame};

    $self->encoding($f->{control}->{encoding}) if $f->{control}->{encoding};

    my @tap = $self->event_tap($f, $num) or return;

    $self->{MADE_ASSERTION} = 1 if $f->{assert};

    my $nesting = $f->{trace}->{nested} || 0;
    my $handles = $self->{handles};
    my $indent = '    ' x $nesting;

    # Local is expensive! Only do it if we really need to.
    local($\, $,) = (undef, '') if $\ || $,;

    for my $set (@tap) {
        my ($hid, $msg) = @$set;
        next unless $msg;
        my $io = $handles->[$hid] or next;

        print $io "\n"
            if $ENV{HARNESS_ACTIVE}
            && $hid == $self->SUPER::OUT_ERR()
            && $self->{_LAST_FH} != $io
            && $msg =~ m/^#\s*Failed( \(TODO\))? test /;


        my (undef, $filename, $lineno, $caller_class) = @{$frame};

        my $is_comment = $msg =~ m/^#/;
        my $is_not_subtest_call = $caller_class ne 'Test::More::subtest';
        my $is_failed_msg = $msg =~ m/Looks like you failed/;
        my $filename_not_within_t_dir = $filename =~ m/^(t|xt)/;

        if ($is_comment && $is_not_subtest_call && !$is_failed_msg && $filename_not_within_t_dir) {
            $msg = $self->_yamilify_message($frame, $e, $msg);
        }
        $msg =~ s/^/$indent/mg if $nesting;
        print $io $msg;
        $self->{_LAST_FH} = $io;
    }
    # print Dumper($self);
    # die 'stop here';
    # print STDERR $num, "\n";
}

use Data::Dumper;

sub finalize2 {
    my ($self, $plan, $count, $failed, $pass, $is_subtest) = @_;
    return;
    foreach my $key (sort keys %{$self->{'+CTX'}}) {
        my $ctx = $self->{'+CTX'}->{$key};
        my ($filename, $lineno) = split(':', $key);
        print "::error file=$filename,line=$lineno,title=Failed Tests::";
        
        foreach my $message (@{ $ctx->{events} }) {
            my $line = $message->{msg};
            $line =~ s/\n/%0A/g;
            print $line;

        }
        print "\n";
    }

    $self->{'+CTX'} = {};
}
 
1;
