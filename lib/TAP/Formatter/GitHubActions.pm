package TAP::Formatter::GitHubActions;

use strict;
use warnings;
use v5.16;
use base 'TAP::Formatter::File';

our $VERSION = '0.2.6_1';

# My file, my terms.
my $TRIPHASIC_REGEX = qr/
  \s*
  Failed\stest                  # Beginning Needle
  (                             # 
    \s*'(?<test_name>[^']+)'    # Test Name [usually last param in assertion]
    \n\s*\#\s*                  # eat-up all the remainder
  )?                            # -- Optional
  \s*
  at\s(?<filename>.+)           # Location: File
  \s*
  line\s(?<line>\d+)            # Location: Line
  \.\n
  (?<context_msg>[\w\W]*)       # Any additional content
/x;

sub open_test {
  my ($self, $test, $parser) = @_;
  # my $session = TAP::Formatter::GitHubActions::Session->new( {
  #     name            => $test,
  #     formatter       => $self,
  #     parser          => $parser,
  #     # passing_todo_ok => $ENV{ALLOW_PASSING_TODOS} ? 1 : 0,
  # } );
  my $session = $self->SUPER::open_test($test, $parser);

  # We'll use the parser as a vessel, afaics there's one parser instance per
  # parallel job.

  # We'll keep track of all output of a test with this.
  $parser->{_fail_msgs} = [''];

  # In an ideal world, we'd just need to listen to `comment` and that should
  # suffice, but `throws_ok` & `lives_ok` report via `unknown`...
  # But this is real life...
  my $handler = sub {
    my $result = shift;

    # on every "failed test", start a new buffer.
    push(@{$parser->{_fail_msgs}}, '') if $result->raw =~ /Failed test/;

    # Don't save "# Subtest" headers
    return if $result->raw =~ /# Subtest/;
    # Don't save the last message, it's useless.
    return if $result->raw =~ /Looks like/;
    return unless $result->raw =~ /^\s*#/;
    # save the message.
    $parser->{_fail_msgs}[-1] .= $result->raw . "\n";
  };

  $parser->callback(comment => $handler);
  $parser->callback(unknown => $handler);

  return $session;
}

sub header {
}

sub summary {
  my ($self, $aggregate, $interrupted) = @_;

  # $self->SUPER::summary($aggregate, $interrupted);

  my $total = $aggregate->total;
  my $passed = $aggregate->passed;

  return if ($total == $passed && !$aggregate->has_problems);

  for my $test ($aggregate->descriptions) {
    my ($parser) = $aggregate->parsers($test);

    next if $parser->passed == $parser->tests_run && !$parser->exit;

    my $failures_per_line = {};
    # First pass, aggregate errors in the same line into a single error.
    # This is mostly cosmetic not to spam the UI that hard.
    for my $line (@{$parser->{_fail_msgs}}) {
      # Skip anything that doesn't look like our TRIPHASIC REGEX
      next unless $line =~ qr/$TRIPHASIC_REGEX/m;
      # Extract all variables
      my ($line, $fail_message, $context_msg) = ($+{line}, $+{test_name} // 'fail test', $+{context_msg});
      $failures_per_line->{$line} //= ();

      # Eat up any trailing whitespace
      chomp($context_msg);
      # Remove indentation before the #
      $context_msg =~ s/^\s*//gm;

      $fail_message = "- $fail_message";
      if ($context_msg) {
        # Indent
        $context_msg =~ s/^/    /gm;
        # Encode all newlines
        # Render a block
        $fail_message .= "\n--- CAPTURED CONTEXT ---";
        $fail_message .= "\n$context_msg";
        $fail_message .= "\n---  END OF CONTEXT  ---";
      }

      push(@{$failures_per_line->{$line}}, $fail_message);
    }

    # Second pass: Print the aggregations
    for my $line (sort keys %$failures_per_line) {
      my $message = join("%0A%0A", @{$failures_per_line->{$line}});
      $message =~ s/\n/%0A/g;

      my $log_line = sprintf(
        "::error file=%s,line=%s,title=Failed Tests::%s",
        $test, $line, $message
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
