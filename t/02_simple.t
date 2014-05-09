#!/usr/bin/perl

# Real test.

# perl -Ilib -I../Git-ClonesManager/lib/ t/02_simple.t

use strict;
use Test::Spec;
use base qw(Test::Spec);

use FindBin ();
use Git::ClonesManager;
use Git::Repository::LogRaw;

my $tmp_base_dir = File::Spec->catdir( $FindBin::RealBin, '..', 'temp' );
mkdir($tmp_base_dir) unless -d $tmp_base_dir;

my $tmp_dir = File::Spec->catdir( $tmp_base_dir, 't-repos-gcm' );
mkdir($tmp_dir) unless -d $tmp_dir;

my $cm_obj = Git::ClonesManager->new( data_path => $tmp_dir, vl => 1 );
my $base_repo_obj = $cm_obj->get_repo_obj(
	'tt-tr1',
	repo_url => 'git@github.com:mj41/tt-tr1.git',
	skip_fetch => 1,
);

sub commit1_struct {
	return {
		author => {
			email => 'mj@mj41.cz',
			gmtime => '1286564447',
			name => 'Michal Jurosz',
			timezone => '+0200'
		},
		commit => '1c283d987b375d901620e8215b0e56e05cddb0c4',
		committer => {
			email => 'mj@mj41.cz',
			gmtime => '1286564447',
			name => 'Michal Jurosz',
			timezone => '+0200'
		},
		items => [
			{
				hash => '9daeafb9864cf43055ae93beb0afd6c7d144bfa4',
				mode => 100644,
				name => 'README',
				parents => [
					{
						hash => '0000000000000000000000000000000000000000',
						mode => '000000',
						status => 'A'
					}
				]
			}
		],
		msg => 'c1',
		parents => [],
		stat => {
			README => {
				lines_added => 1,
				lines_removed => 0
			}
		},
		tree => '26d219526a6a64efcd2bf566f04735f798a50084'
	};
}

sub commit2_struct {
	return {
		author => {
			email => 'mj@mj41.cz',
			gmtime => '1286564504',
			name => 'Michal Jurosz',
			timezone => '+0200'
		},
		commit => '37305807edcc52f0b83b1eb0264def1da46f49aa',
		committer => {
			email => 'mj@mj41.cz',
			gmtime => '1286564504',
			name => 'Michal Jurosz',
			timezone => '+0200'
		},
		items => [
			{
				hash => '253ebd5273da6863b84103742c14d0ef631029b1',
				mode => 100644,
				name => 'README',
				parents => [
					{
						hash => '9daeafb9864cf43055ae93beb0afd6c7d144bfa4',
						mode => 100644,
						status => 'M'
					}
				]
			}
		],
		msg => 'c2',
		parents => [
			'1c283d987b375d901620e8215b0e56e05cddb0c4'
		],
		stat => {
			README => {
				lines_added => 1,
				lines_removed => 1
			}
		},
		tree => '2d4187ac4f33aa739b7bffac2ef186eec53f2d8e'
	};
}


describe "git log structure of" => sub {
	my $git_lograw_obj = Git::Repository::LogRaw->new( $base_repo_obj, 1 );
	my $log = $git_lograw_obj->get_log( {} );

	it "commit 1" => sub {
		is_deeply( $log->[0], commit1_struct() );
	};
	it "commit 2" => sub {
		is_deeply( $log->[1], commit2_struct() );
	};
};

runtests unless caller;
