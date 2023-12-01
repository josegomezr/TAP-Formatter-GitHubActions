package TAP::Formatter::GitHubActions;

use strict;
use warnings;
use v5.16;
use base 'TAP::Formatter::File';
# use TAP::Parser::YAMLish::Reader;

our $VERSION = '0.3.0_1';

# My file, my terms.
my $TRIPHASIC_REGEX = qr/
\s*
  (?<test_name>
    Failed\stest                  # Beginning Needle
    (?:\s*'[^']+')?    # Test Name [usually last param in assertion]
  )                            # -- Optional
  \s*
  at\s(?<filename>.+)           # Location: File
  \s*
  line\s(?<line>\d+)\.          # Location: Line
  (\n)?
  (?<context_msg>[\w\W]*)       # Any additional content
/mx;

sub open_test {
  my ($self, $test, $parser) = @_;
  my $session = $self->SUPER::open_test($test, $parser);

  # We'll use the parser as a vessel, afaics there's one parser instance per
  # parallel job.

  # We'll keep track of all output of a test with this.
  $parser->{_tap_comments} = [];
  $parser->{_tap_yaml} = [];

  # In an ideal world, we'd just need to listen to `comment` and that should
  # suffice, but `throws_ok` & `lives_ok` report via `unknown`...
  # But this is real life...
  # so...
  my $handler =  sub {
    my $result = shift;
    $result = $result->raw;
    # Skip all messages that are not comments
    return unless $result =~ /^\s*#/;

    # cleanup the message
    $result =~ s/\s*#\s*//;
    # Skip Subtests
    return if $result =~ /^Subtest/;
    # Skip Subtests
    return if $result =~ m/^Looks like/;

    # Push a new buffer on every failed test
    push(@{$parser->{_tap_comments}}, '') if $result =~ /^Failed test/;
    # Just in case something is printed before reachign a "Failed test", add a buffer
    push(@{$parser->{_tap_comments}}, "Failed test\n") unless defined $parser->{_tap_comments}[-1];

    $parser->{_tap_comments}[-1] .= $result . "\n";
  };

  $parser->callback(unknown => $handler);
  $parser->callback(comment => $handler);

  # Enable YAML Support
  $parser->version(13);
  $parser->callback(yaml => sub {
    push @{$parser->{_tap_yaml}}, $_[0]->data;
  });

  return $session;
}

sub header { }

sub _process_captured_yaml_comments {
  my ($self, $parser, $test) = @_;

  $parser->{_failures_per_line} //= {};
  foreach my $yaml (@{$parser->{_tap_yaml}}) {
    my $line = $yaml->{at}->{line};

    my $msg = $yaml->{message};
    $parser->{_failures_per_line}->{$line} //= ();
    push @{$parser->{_failures_per_line}->{$line}}, $msg;
  }
}

sub _process_captured_tap_comments {
  my ($self, $parser, $test) = @_;

  $parser->{_failures_per_line} //= {};

  foreach my $line (@{$parser->{_tap_comments}}) {
    chomp($line);
    # Skip anything that doesn't look like our TRIPHASIC REGEX

    next unless $line =~ qr/$TRIPHASIC_REGEX/m;
    # Extract all variables
    my ($line, $fail_message, $context_msg) = ($+{line}, $+{test_name} // 'fail test', $+{context_msg});
    $parser->{_failures_per_line}->{$line} //= ();

    # Eat up any trailing whitespace
    chomp($context_msg);
    # Remove indentation before the #
    $context_msg =~ s/^\s*//gm;

    $fail_message = "$fail_message";
    if ($context_msg) {
      # Indent
      $context_msg =~ s/^/    /gm;
      # Encode all newlines
      # Render a block
      $fail_message .= "\n$context_msg";
    }

    push(@{$parser->{_failures_per_line}->{$line}}, $fail_message);
  }

  return $parser->{_failures_per_line};
}

# this needs a re-design the moment I understand better all parts involved...
sub summary {
  my ($self, $aggregate, $interrupted) = @_;
  # $self->SUPER::summary($aggregate, $interrupted);
  $self->_output("\n= GitHub Actions Report =\n");

  my $total = $aggregate->total;
  my $passed = $aggregate->passed;

  return if ($total == $passed && !$aggregate->has_problems);

  for my $test ($aggregate->descriptions) {
    my ($parser) = $aggregate->parsers($test);

    next if $parser->passed == $parser->tests_run && !$parser->exit;

    # First pass, aggregate errors in the same line into a single error.
    # This is mostly cosmetic not to spam the UI that hard.
    $self->_process_captured_tap_comments($parser, $test);
    # YAML overwrites TAP Comments.
    $self->_process_captured_yaml_comments($parser, $test);

    my $failures_per_line = $parser->{_failures_per_line};

    # Second pass: Print the aggregations
    for my $line (sort keys %$failures_per_line) {
      my ($title, $message) = split(/\n/, join("\n\n", @{$failures_per_line->{$line}}), 2);
      next unless $title =~ /^Failed test/;
      $title =~ s/\n/%0A/g;
      $message //= "";
      $message = "::--- CAPTURED CONTEXT ---\n$message\n---  END OF CONTEXT  ---" if $message;
      $message =~ s/\n/%0A/g;

      my $log_line = sprintf(
        "::error file=%s,line=%s,title=%s%s",
        $test, $line, $title, $message
      );

      $self->_output("$log_line\n");
    }
  }
}

1;
__END__

=head1 NAME

TAP::Formatter::GitHubActions - TAP Formatter for GitHub Actions

=head1 SYNOPSIS

On the command line, with I<prove>:

  $ prove --merge --formatter TAP::Formatter::GitHubActions ...

You can also use a C<.proverc> file with
  
  # .proverc contents
  --lib
  --merge
  --formatter TAP::Formatter::GitHubActions

And then invoke I<prove> without flags:

  $ prove

=head2 IMPORTANT NOTE

This formatter B<needs> the C<--merge> flag, else it won't be able to process
the comments to produce GitHub-Actions-compatible output.

=head1 DESCRIPTION

C<TAP::Formatter::GitHubActions> provides GitHub-Actions-compatible output for
I<prove>.

=head1 SEE ALSO

- JUnit Formatter: L<TAP::Formatter::JUnit>

- L<GitHub Workflow Commands Documentation|https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-error-message>

=head1 AUTHOR

Jose, D. Gomez R. E<lt>1josegomezr [AT] gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023 by Jose D. Gomez R.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.38.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
