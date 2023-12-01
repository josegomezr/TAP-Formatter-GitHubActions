package TAP::Formatter::GitHubActions;

use strict;
use warnings;
use v5.16;
use base 'TAP::Formatter::File';
our $VERSION = '0.3.0_4';

# My file, my terms.
my $TRIPHASIC_REGEX = qr/
\s*
  (?<test_name>                   # Test header
    Failed\stest                  
    (?:\s*'[^']+')?               # Test name [usually last param in an assertion, optional]
  )
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

  # force verbosity to be able to read comments, yamls & unknowns.
  $self->verbosity(1);

  # We'll use the parser as a vessel, afaics there's one parser instance per
  # parallel job.

  # We'll keep track of all output of a test with this.
  $parser->{_tap_comments} = [];
  $parser->{_tap_yaml} = [];

  # In an ideal world, we'd just need to listen to `comment` and that should
  # suffice, but `throws_ok` & `lives_ok` report via `unknown`...
  # But this is real life...
  # so...
  my $handler = sub {
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

    # Just in case something is printed before reaching a "Failed test":
    #   add a new buffer
    push(@{$parser->{_tap_comments}}, "Failed test\n")
      unless defined $parser->{_tap_comments}[-1];

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
    $msg =~ s/\n.+//gm if $msg =~ /^Failed test /;
    chomp($msg);

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
  $self->SUPER::summary($aggregate, $interrupted);

  my $total = $aggregate->total;
  my $passed = $aggregate->passed;

  return if ($total == $passed && !$aggregate->has_problems);

  $self->_output("\n= GitHub Actions Report =\n");

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
    # TODO: this really needs some love, is a nightmare of cleaning up emptyspaces
    for my $line (sort keys %$failures_per_line) {
      my ($title, $message) = split(/\n/, join("\n\n", @{$failures_per_line->{$line}}), 2);
      next unless $title =~ /^Failed test/;

      $message //= "";
      $message =~ s/^\n//;
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

It parses TAP output and tries it's best to guess where errors are located.
For more accurate results, use in cojunction with
L<Test2::Formatter::YAMLEnhancedTAP>.

L<Test2::Formatter::YAMLEnhancedTAP> enriches the TAP output generated by
L<Test2> and friends (L<Test::More>, L<Test::Most>) with an additional context
in YAML format (compliant with TAP version 13) that includes the precise
location of the failure.

=head1 SEE ALSO

=over 1

- L<TAP::Formatter::JUnit>: JUnit XML output for your Tests!

- L<Test2::Formatter::YAMLEnhancedTAP>: Enhanced TAP Output for your tests!

- L<GitHub Workflow Commands Documentation|https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-error-message>: For more information about the output syntax

=back

=head1 AUTHOR

Jose, D. Gomez R. E<lt>1josegomezr [AT] gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023 by Jose D. Gomez R.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.38.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
