use strict;
use warnings;
use v5.16;
use Test::More;
use IO::Scalar;
use TAP::Harness;

# everything down here is *VERY* influenced by:
# https://github.com/bleargh45/TAP-Formatter-JUnit/blob/main/t/formatter.t
# 100x kudos to authors there! 🎉

sub slurp {
  open(my $fh, '<', shift) or die $!;
  local $/ = undef;
  my $content = <$fh>;
  close($fh);
  return $content;
}

my @tests = grep { -f $_ } <t/fixtures/tests/*>;

plan tests => 1 + scalar(@tests);
use_ok('TAP::Formatter::GitHubActions');

foreach my $test (@tests) {
  (my $output = $test) =~ s{(/fixtures)/tests/}{$1/output/};

  my $expected = slurp($output);

  my $received = '';
  open(my $fh, '>', \$received);

  eval {
    my $harness = TAP::Harness->new({
        stdout => $fh,
        # merge => 1,
        formatter_class => 'TAP::Formatter::GitHubActions',
    });
    $harness->runtests($test);
  };

  $expected = (split/= GitHub Actions Report =\n/, $expected, 2)[1] // '';
  $received = (split/= GitHub Actions Report =\n/, $received, 2)[1] // '';
  chomp($expected);
  chomp($received);
  my $fail;
  is($received, $expected, $test) or ($fail = 1);
  
  if ($fail) {
    print "\n== $output ==\n";
    print $received;
    print "\n====\n";
  } ;
  
}
