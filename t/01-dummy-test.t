#!/usr/bin/env perl

use strict;
use warnings;
use v5.26;

use Test::Most;
use Test::Warnings;

is(1, 1);
is(1, 0);
is(1, 1, 'equality [pass]');
is(1, 0, 'equality [not pass]');

diag('a top level diag');
note('a top level note');

lives_ok { print "a message\n" } 'lives ok [pass]';
lives_ok { print "with a message\n"; } 'lives ok [not pass]';
lives_ok { print "with a message and a newline\n"; } 'lives ok [not pass]';

subtest "L1: one level" => sub {
  is(1, 1, 'L1: equality [pass]');
  is(1, 0, 'L1: equality [not pass]');

  diag('L1: a top level diag');
  note('L1: a top level note');

  lives_ok { print "L1: a message\n" } 'L1: lives ok [pass]';
  lives_ok { die "L1: with a message\n"; } 'L1: lives ok [not pass]';
  lives_ok { die "L1: with a message and a newline\n"; } 'L1: lives ok [not pass]';
};

subtest "L2: one level" => sub {
  diag('L2: a top level diag');
  note('L2: a top level note');
  subtest "L2.1: another level deep" => sub {
    diag('L2.1: a top level diag');
    note('L2.1: a top level note');
    is(1, 1, 'L2: equality [pass]');
    is(1, 0, 'L2: equality [not pass]');

    lives_ok { print "L2: a message\n" } 'L2: lives ok [pass]';
    lives_ok { die "L2: with a message\n"; } 'L2: lives ok [not pass]';
    lives_ok { die "L2: with a message and a newline\n"; } 'L2: lives ok [not pass]';
  };
};

my $astr = 'a very long string here a very long string here a very long string here a very long string here a very long string here a very long string here a very long string here a very long string here a very long string here';
ok(is($astr, $astr, 'L0: equality [pass]'));
ok(is($astr, $astr . '--', 'L2: equality [not pass]'));
ok(is($astr, $astr . '--', 'L2: equality [not pass]'), 'should not fail');

done_testing();
