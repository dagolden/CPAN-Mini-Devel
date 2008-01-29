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
        perl => 5.006,
        'CPAN' => 1.92, 
        'CPAN::Mini' => 0.566,
        'CPAN::Tarzip' => 0, 
        'File::Spec' => 3.27, 
        'File::Temp' => 0.20, 
    },
    build_requires => {
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

