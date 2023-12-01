# Needed until preaction/Log-Any#105 is solved.
requires 'Storable', '>= 3.06';

on 'test' => sub {
    requires 'Test2::Formatter::YAMLEnhancedTAP', '>= 0.0.3';
    requires 'Test::Most';
    requires 'Test::Warnings';
};

on 'develop' => sub {
    requires 'Code::TidyAll';
    requires 'Perl::Critic';
    requires 'Perl::Critic::Community';
    requires 'Perl::Tidy', '== 20230912';
};
