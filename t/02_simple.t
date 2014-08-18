#!/usr/bin/perl

# Real test.

# perl -Ilib -I../Git-ClonesManager/lib/ t/02_simple.t

use strict;
use Test::Spec;
use base qw(Test::Spec);

use FindBin ();
use Git::ClonesManager;
use Git::Repository::LogRaw;


sub get_clonesmanager_obj {
	my ( $project_alias ) = @_;

	my $repos_clones_base_dir = File::Spec->catdir( $FindBin::RealBin, '..', 'temp' );
	mkdir($repos_clones_base_dir) unless -d $repos_clones_base_dir;

	my $repos_clones_dir = File::Spec->catdir( $repos_clones_base_dir, 't-repos-gcm' );
	mkdir($repos_clones_dir) unless -d $repos_clones_dir;

	my $cm_obj = Git::ClonesManager->new( data_path => $repos_clones_dir, vl => 1 );
	return $cm_obj;
}

sub commit1_struct {
	return {
		author => {
			email => 'kal@houby.eu',
			gmtime => '1153520604',
			name => 'Karel Lysohlavka',
			timezone => '+0000'
		},
		commit => 'c1845d7580a091c1718e083cc5e90751cf3853f3',
		committer => {
			email => 'kal@houby.eu',
			gmtime => '1153520726',
			name => 'Karel Lysohlavka',
			timezone => '+0000'
		},
		items => [
			{
				hash => '0066197c4d0a2bc0bad6418c0341455b6789fd14',
				mode => 100644,
				name => 'fileR1.txt',
				parents => [
					{
						hash => '0000000000000000000000000000000000000000',
						mode => '000000',
						status => 'A'
					}
				]
			}
		],
		msg => 'commit_master_001',
		parents => [],
		stat => {
			'fileR1.txt' => {
				lines_added => 2,
				lines_removed => 0
			}
		},
		tree => 'd9348511742d60519a93e8eb3c15611baa9d1570'
	};
}

sub commit2_struct {
	return {
		author => {
			email => 'kal@houby.eu',
			gmtime => '1153528404',
			name => 'Karel Lysohlavka',
			timezone => '+0200'
		},
		commit => 'ac03197f450c74342f76f6eab41569a26fa3baaa',
		committer => {
			email => 'josef.p.muchomurka@mushrooms.com',
			gmtime => '1153562645',
			name => 'Josef Pepa Muchomurka',
			timezone => '+0300'
		},
		items => [
			{
				hash => '18b1d61b237084da18859e2029ad88c9cd3c50c0',
				mode => 100644,
				name => 'fileR1.txt',
				parents => [
					{
						hash => '0066197c4d0a2bc0bad6418c0341455b6789fd14',
						mode => 100644,
						status => 'M'
					}
				]
			}
		],
		msg => 'Commit master 002

Commit description line 1
Commit description line 2
Commit description line 3

Commit description line 5',

		parents => [
			'c1845d7580a091c1718e083cc5e90751cf3853f3'
		],
		stat => {
			'fileR1.txt' => {
				lines_added => 3,
				lines_removed => 0
			}
		},
		tree => 'e59a25ae12f625398e5e4cb536b7cffea8319f97'
	};
}


my $verbose_level = $ARGV[0] // 1;
my $skip_fetch = $ARGV[1] // 1;

my $project_alias = 'git-trepo';
my $cm_obj = get_clonesmanager_obj($project_alias);
my $base_repo_obj = $cm_obj->get_repo_obj(
	$project_alias,
	repo_url => 'git@github.com:mj41/git-trepo.git',
	skip_fetch => $skip_fetch,
);

describe "git log structure of" => sub {
	my $git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, $verbose_level );
	my $log = $git_lograw_obj->get_log( {} );
	it "commit 1" => sub {
		is_deeply( $log->[0], commit1_struct() );
	};
	it "commit 2" => sub {
		is_deeply( $log->[1], commit2_struct() );
	};
};

describe "option" => sub {
	it "number_limit" => sub {
		my $git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, $verbose_level );
		my $log = $git_lograw_obj->get_log( {}, number_limit => 1 );
		# todo - "-n 1" of "git log" is applied before "--reverse --date-order ..."
		#is_deeply( $log, [ commit1_struct() ] );
		is( scalar @$log, 1 );
	};

	it "rev_range" => sub {
		my $git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, $verbose_level );
		my $log = $git_lograw_obj->get_log( {}, rev_range => commit2_struct()->{commit} );
		is_deeply( $log, [ commit1_struct(), commit2_struct() ] );
	};

	it "only_rev" => sub {
		my $git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, $verbose_level );
		my $log = $git_lograw_obj->get_log( {}, only_rev => commit2_struct()->{commit} );
		is_deeply( $log, [ commit2_struct() ] );
	};

	it "branch, rev_range" => sub {
		my $git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, $verbose_level );
		my $log = $git_lograw_obj->get_log( {}, branch => 'br1', rev_range => 'HEAD..HEAD~1' );
		is( $log->[0]{commit}, '5035bb5592d18809b9c3ef2ba352d080697d2b40' );
	};
};

runtests unless caller;
