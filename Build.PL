use 5.006;
use strict;
use lib 'inc';
eval "require Pod::WikiDoc";
my $class = $@ ? "Module::Build" : "Module::Build::WikiDoc";
eval "require $class";
$class->new( 
    module_name         => 'CPAN::Mini::Devel',
    dist_author         => 'David A. Golden <dagolden@cpan.org>',
    license             => 'apache',
    create_readme       => 1,
    create_makefile_pl  => 'traditional',
    requires => {
        'perl' => 5.006,
        'CPAN' => 1.92, 
        'CPAN::HandleConfig' => 0, # 5.405725 is new
        'CPAN::Mini' => 0.567,
        'CPAN::Tarzip' => 0, 
        'File::Basename' => 0,
        'File::Path' => 0,
        'File::Spec' => 3.27, 
        'File::Temp' => 0.20, 
    },
    build_requires => {
        'Test::More' => 0.62, # 0.47 in perl 5.006002; 0.62 in perl 5.008008; 
    },
    meta_merge            => { 
        no_index => { 
            directory => [ qw{
                examples
                inc
            }],
        },
        resources => {
            repository => 'http://dagolden.googlecode.com/svn/'
        },
    },
)->create_build_script;

