#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;

use Git::Repository;
use Git::Repository::LogRaw ();

my $git_repo_path = $ARGV[0] // die "No path to git repo provided.";
my $verbose_level = $ARGV[1] // 1;
my $rev_range = $ARGV[2] // undef;

my $base_repo_obj = Git::Repository->new( git_dir => $git_repo_path );

my $git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, $verbose_level );

my %args = (
    reverse => 1,
);
$args{rev_range} = $rev_range if $rev_range;

my $log = $git_lograw_obj->get_log( {}, %args );
print Dumper( $log );
