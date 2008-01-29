package CPAN::Mini::Devel;
use 5.006;
use strict;
use warnings;
our $VERSION = '0.01'; 
$VERSION = eval $VERSION; ## no critic

use Config;
use CPAN::Mini;
use CPAN; 
use CPAN::Tarzip;
use CPAN::HandleConfig;
use File::Temp 0.20;
use File::Spec;
use File::Path ();

our @ISA = 'CPAN::Mini';

#--------------------------------------------------------------------------#
# globals
#--------------------------------------------------------------------------#

my $tmp_dir = File::Temp->newdir( 'CPAN-Mini-Devel-XXXXXXX', 
    DIR => File::Spec->tmpdir,
);

#--------------------------------------------------------------------------#
# Extend index methods to miror find-ls.gz
#--------------------------------------------------------------------------#

my $index_file = 'indices/find-ls.gz';

sub _fixed_mirrors {
    my $self = shift;
    return ($index_file, $self->SUPER::_fixed_mirrors);
}

sub mirror_indices {
    my $self = shift;
    File::Path::mkpath(File::Spec->catdir($self->{scratch}, 'indices'));
    $self->SUPER::mirror_indices;
}

sub install_indices {
    my $self = shift;
    for my $dir (qw(indices)) {
        my $needed = File::Spec->catdir($self->{local}, $dir);
        File::Path::mkpath($needed, $self->{trace}, $self->{dirmode});
        die "couldn't create $needed: $!" unless -d $needed;
    }
    $self->SUPER::install_indices
}

#--------------------------------------------------------------------------#
# Extend update_mirror to add developer versions
#--------------------------------------------------------------------------#

sub update_mirror {
	my $self  = shift;
	$self = $self->new(@_) unless ref $self;

    $self->trace( "Using CPAN::Mini::Devel\n" );

	# mirrored tracks the already done, keyed by filename
	# 1 = local-checked, 2 = remote-mirrored
	$self->mirror_indices;

	return unless $self->{force} or $self->{changes_made};

    $self->_mirror_extras;

    ## CPAN::Mini::Devel addition using find-ls.gz
    my $local_index =  File::Spec->catfile(
        $self->{scratch},
        qw(indices find-ls.gz)
    );
    $self->trace("Scanning find-ls.gz...\n");
    for my $base_id ( @{ _parse_module_index( $local_index ) } ) {
        (my $pretty_id = $base_id) =~ s{^(((.).).+)$}{$3/$2/$1};
        next if $self->_filter_module({
                module  => $pretty_id,
                path    => $pretty_id,
            });
        $self->trace("authors/id/$pretty_id\n");
#        $self->mirror_file("authors/id/$pretty_id", 1);
    };

    
    ## Continue with the rest, will pick up any odd distributions
    ## that were successfully indexed but looked weird in find-ls.gz

    # now walk the packages list
    my $details = File::Spec->catfile(
        $self->{scratch},
        qw(modules 02packages.details.txt.gz)
    );

    my $gz = Compress::Zlib::gzopen($details, "rb")
        or die "Cannot open details: $Compress::Zlib::gzerrno";

    my $inheader = 1;
    while ($gz->gzreadline($_) > 0) {
        if ($inheader) {
            $inheader = 0 unless /\S/;
            next;
        }

        my ($module, $version, $path) = split;
        next if $self->_filter_module({
                module  => $module,
                version => $version,
                path    => $path,
            });

        $self->mirror_file("authors/id/$path", 1);
    }

    $self->_install_indices;

    # eliminate files we don't need
    $self->clean_unmirrored unless $self->{skip_cleanup};
    return $self->{changes_made};
}

#--------------------------------------------------------------------------#
# private variables and functions
#--------------------------------------------------------------------------#

my $module_index_re = qr{
    ^\s href="\.\./authors/id/./../    # skip prelude 
    ([^"]+)                     # capture to next dquote mark
    .+? </a>                    # skip to end of hyperlink
    \s+                         # skip spaces
    \S+                         # skip size
    \s+                         # skip spaces
    (\S+)                       # capture day
    \s+                         # skip spaces
    (\S+)                       # capture month 
    \s+                         # skip spaces
    (\S+)                       # capture year
}xms; 

my %months = ( 
    Jan => '01', Feb => '02', Mar => '03', Apr => '04', May => '05',
    Jun => '06', Jul => '07', Aug => '08', Sep => '09', Oct => '10',
    Nov => '11', Dec => '12'
);

# standard regexes
my %re = (
    perls => qr{[^/]+/(?:perl|parrot|kurila|ponie|Perl6-Pugs)-?\d},
    archive => qr{\.(?:tar\.(?:bz2|gz|Z)|t(?:gz|bz)|zip)$}i,
    target_dir => qr{
        ^(?:
            modules/by-module/[^/]+/ | 
            modules/by-category/[^/]+/ | 
            authors/id/./../
        )
    }x,
);

# split into "AUTHOR/Name" and "Version"
$re{split_them} = qr{^(.+)-([^-]+)$re{archive}$};

# matches "AUTHOR/tarbal.suffix" and not "AUTHOR/subdir/whatever"
$re{get_base_id} = qr{$re{target_dir}([^/]+/[^/]+)$};

#--------------------------------------------------------------------------#
# _parse_module_index
#
# parse index and return array_ref of distributions in reverse date order
#--------------------------------------------------------------------------#-

sub _parse_module_index {
    my ($filename) = @_;

    local *FH;
    tie *FH, 'CPAN::Tarzip', $filename;

    my %latest;
    my %latest_dev;

    while ( defined ( my $line = <FH> ) ) {
        my %stat;
        @stat{qw/inode blocks perms links owner group size datetime name linkname/}
            = split q{ }, $line;
        
        # skip directories, symlinks and things that aren't a tarball
        next if $stat{perms} eq "l" || substr($stat{perms},0,1) eq "d";
        next unless $stat{name} =~ $re{target_dir};
        next unless $stat{name} =~ $re{archive};

        # skip if not AUTHOR/tarball 
        # skip perls
        my ($base_id) = $stat{name} =~ $re{get_base_id};
        next unless $base_id; 
        next if $base_id =~ $re{perls};

        # split into "AUTHOR/Name" and "Version"
        # skip if doesn't dist doesn't have a proper version number
        my ($base_dist, $base_version) = $base_id =~ $re{split_them};
        next unless defined $base_dist && defined $base_version; 

        # record developer and regular releases separately
        my $tracker = ( $base_version =~ m{_} ) ? \%latest_dev : \%latest;

        $tracker->{$base_dist} ||= { datetime => 0 };
        if ( $stat{datetime} > $tracker->{$base_dist}{datetime} ) {
            $tracker->{$base_dist} = { 
                datetime => $stat{datetime}, 
                base_id => $base_id
            };
        }
    }

    # assemble from two sets keyed on base_dist (name) into one set 
    # keyed on base_id (name-version.suffix)
    
    my %dists;
    for my $name ( keys %latest ) {
        $dists{ $latest{$name}{base_id} } = $latest{$name}{datetime} 
    }

    # for dev versions, it must be newer than the latest version of
    # the same base_dist

    for my $name ( keys %latest_dev ) {
        next if exists $latest{$name} && 
            $latest{$name}{datetime} > $latest_dev{$name}{datetime};
        $dists{ $latest_dev{$name}{base_id} } = $latest_dev{$name}{datetime} 
    }

#    return [ sort { $dists{$b} <=> $dists{$a} } keys %dists ];
    return [ sort keys %dists ];
}

1; #modules must return true

__END__

#--------------------------------------------------------------------------#
# pod documentation 
#--------------------------------------------------------------------------#

=begin wikidoc

= NAME

CPAN::Mini::Devel - Create CPAN::Mini mirror with developer releases

= VERSION

This documentation describes version %%VERSION%%.

= SYNOPSIS

    $ minicpan -c CPAN::Mini::Devel

= DESCRIPTION

Normally, [CPAN::Mini] creates a minimal CPAN mirror with the latest version of
each distribution, but excluding developer releases (those with an underscore
in the version number, like 0.10_01).  

CPAN::Mini::Devel enhances CPAN::Mini to include the latest developer and
non-developer release in the mirror. For example, if Foo-Bar-0.01,
Foo-Bar-0.02, Foo-Bar-0.03_01 and Foo-Bar-0.03_02 are on CPAN, only
Foo-Bar-0.02 and Foo-Bar 0.03_02 will be mirrored. This is particularly useful
for creating a local mirror for smoke testing.

CPAN::Mini::Devel also mirrors the {indices/find-ls.gz} file, which is used
to identify developer releases.

= USAGE

See [Mini::CPAN].

= BUGS

Please report any bugs or feature using the CPAN Request Tracker.  
Bugs can be submitted through the web interface at 
[http://rt.cpan.org/Dist/Display.html?Queue=CPAN-Mini-Devel]

When submitting a bug or request, please include a test-file or a patch to an
existing test-file that illustrates the bug or desired feature.

= SEE ALSO

* [CPAN::Mini]

= AUTHOR

David A. Golden (DAGOLDEN)

= COPYRIGHT AND LICENSE

Copyright (c) 2008 by David A. Golden

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at 
[http://www.apache.org/licenses/LICENSE-2.0]

Files produced as output though the use of this software, shall not be
considered Derivative Works, but shall be considered the original work of the
Licensor.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=end wikidoc

=cut
