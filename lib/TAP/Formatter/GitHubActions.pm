package TAP::Formatter::GitHubActions;

use strict;
use warnings;
use v5.16;
use base 'TAP::Formatter::File';
use TAP::Parser::YAMLish::Reader;
use YAML::PP qw(Load);

my $yr = TAP::Parser::YAMLish::Reader->new;
our $VERSION = '0.2.6_DEVEL2';

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

sub _should_inspect_yaml {
  return ($ENV{T2_FORMATTER} // '') =~ m/YAMLEnhancedTAP$/;
}

sub open_test {
  my ($self, $test, $parser) = @_;
  my $session = $self->SUPER::open_test($test, $parser);

  $self->{mode} = $self->_should_inspect_yaml() ? 'yaml' : 'comments';

  # We'll use the parser as a vessel, afaics there's one parser instance per
  # parallel job.

  # We'll keep track of all output of a test with this.
  $parser->{_tap_comments} = [''];
  $parser->{_tap_yaml} = [];

  # In an ideal world, we'd just need to listen to `comment` and that should
  # suffice, but `throws_ok` & `lives_ok` report via `unknown`...
  # But this is real life...
  my $handler = sub {
    my $result = shift;
    # on every "failed test", start a new buffer.
    push(@{$parser->{_tap_comments}}, '') if $result->raw =~ /Failed test/;

    # Don't save "# Subtest" headers
    return if $result->raw =~ /# Subtest/;
    # Don't save the last message, it's useless.
    return if $result->raw =~ /Looks like/;
    return unless $result->raw =~ /^\s*#/;
    # save the message.
    $parser->{_tap_comments}[-1] .= $result->raw . "\n";
  };

  if (!$self->_should_inspect_yaml()) {
    # Legacy parsing
    $parser->callback(comment => $handler);
    $parser->callback(unknown => $handler);
    return $session;
  }

  # Enable YAML Support
  $parser->version(13);
  # Use YAML annotations instead.
  $parser->callback(yaml => sub {
    my $result = shift->raw();
    # de-indent documents
    $result =~ /^\s*/;
    my $pattern = ' ' x $+[0];
    $result =~ s/^$pattern//gm;

    push @{$parser->{_tap_yaml}}, $result;
  });

  return $session;
}

sub header {}

sub _process_captured_yaml_comments {
  my ($self, $parser, $test) = @_;

  my $failures_per_line = {};
  for my $yaml_doc (@{$parser->{_tap_yaml}}) {
    my $yaml = Load($yaml_doc);
    my $line = $yaml->{at}->{line};

    $failures_per_line->{$line} //= ();

    my $msg = $yaml->{message};

    # if it begins with failed test, let's put a mark on it
    if($msg =~ m/^Failed test/){
      $msg =~ s/\n//gm;
      $msg = "- $msg";
    }else{
      # else indent it
      $msg =~ s/^/  /gm unless $yaml->{message} =~ m/^Failed test/;
    }

    push @{$failures_per_line->{$line}}, $msg;
  }

  return $failures_per_line;
}

sub _process_captured_tap_comments {
  my ($self, $parser, $test) = @_;

  my $failures_per_line = {};

  for my $line (@{$parser->{_tap_comments}}) {
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
      $fail_message .= "\n$context_msg";
    }

    push(@{$failures_per_line->{$line}}, $fail_message);
  }

  return $failures_per_line;
}

# this needs a re-design the moment I understand better all parts involved...
sub summary {
  my ($self, $aggregate, $interrupted) = @_;
  $self->SUPER::summary($aggregate, $interrupted);

  my $total = $aggregate->total;
  my $passed = $aggregate->passed;

  return if ($total == $passed && !$aggregate->has_problems);

  for my $test ($aggregate->descriptions) {
    my ($parser) = $aggregate->parsers($test);

    next if $parser->passed == $parser->tests_run && !$parser->exit;

    my $failures_per_line;

    # First pass, aggregate errors in the same line into a single error.
    # This is mostly cosmetic not to spam the UI that hard.
    if ($self->{mode} eq 'yaml') {
      $failures_per_line = $self->_process_captured_yaml_comments($parser, $test);
    }elsif ($self->{mode} eq 'comments') {
      $failures_per_line = $self->_process_captured_tap_comments($parser, $test);
    }else{
      die 'Unknown mode of operation';
    }

    # Second pass: Print the aggregations
    for my $line (sort keys %$failures_per_line) {
      my $message = join("%0A%0A", @{$failures_per_line->{$line}});
      $message = "--- CAPTURED CONTEXT ---\n$message\n---  END OF CONTEXT  ---";
      

      next if $self->{mode} eq 'yaml' && !($message =~ m/Failed test/);

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
