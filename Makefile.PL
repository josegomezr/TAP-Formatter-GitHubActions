use 5.016;

use strict;
use warnings;

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'TAP::Formatter::GitHubActions',
    VERSION_FROM      => 'lib/TAP/Formatter/GitHubActions.pm',
    PREREQ_PM         => {
        'TAP::Harness' => 3.12,
    },
    AUTHOR            => 'Jose D. Gomez R. <1josegomezr@gmail.com>',
    #LICENSE           => 'perl',
    #Value must be from legacy list of licenses here
    #https://metacpan.org/pod/Module::Build::API
);
