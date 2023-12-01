package Test2::Formatter::YAMLEnhancedTAP;

use strict;
use warnings;
use TAP::Parser::YAMLish::Writer;
use base 'Test2::Formatter::TAP';

# Private: TAP::Parser::YAMLish::Writer instance to write YAML TAP snippets
#          it didn't really like YAML::PP in the output for whatever reason
my $_yaml_writer = TAP::Parser::YAMLish::Writer->new;

sub _yamilify_message {
  my ($self, $frame, $event, $message) = @_;
  my (undef, $filename, $lineno, $caller_class) = @{$frame};

  my $yaml = "";
  # Cleanup comments
  $message =~ s/#\s+//gm;
  # Cleanup extra newlines
  chomp($message);

  # Build the YAML.
  $_yaml_writer->write({
      at => {
        test_num => 0,
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

#
sub print_optimal_pass {
  my $self = shift;
  my $ret = $self->SUPER::print_optimal_pass(@_);
  $self->{_optimal_pass_happened} = $ret;
  return $ret;
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
  local ($\, $,) = (undef, '') if $\ || $,;

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

    $msg = $self->_yamilify_message($frame, $e, $msg)
      if $is_comment
      && $is_not_subtest_call
      && !$is_failed_msg
      && $filename_not_within_t_dir;

    $msg =~ s/^/$indent/mg if $nesting;
    print $io $msg;
    $self->{_LAST_FH} = $io;
  }
}

1;
