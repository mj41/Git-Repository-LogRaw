package Git::Repository::LogRaw;

use strict;
use warnings;
use Data::Dumper;

sub new {
	my ( $class, $repo, $verbose_level ) = @_;

	my $self = {};
	$self->{repo} = $repo;
	$self->{vl} = $verbose_level // 3;
	$self->{err_msg} = undef;
	bless $self, $class;
	return $self;
}

sub dump_line {
	my ($self, $src_line, %arg) = @_;
	my $line = $src_line;
	$line =~ s{\0}{‖}g;
	return $line;
}

sub short_str {
	my ( $self, $str, $max_len ) = @_;
	$max_len ||= 250;

	return $self->dump_line($str) if length($str) <= $max_len;
	return $self->dump_line(
		substr( $str, 0, $max_len-3 ) . "..."
	);
}

sub one_item_parser_err {
	my ( $self, $err_msg, $line, $item_info ) = @_;

	$line =~ m/\G (.*) /gcx;
	my $line_end = $self->short_str( $1 );
	return $err_msg . " - not parsed part '" . $self->dump_line($line_end) . "'" . "\n".Dumper($item_info);
}

sub parse_one_item_begin {
	my ( $self, $line, $item_num ) = @_;

	if ( $self->{vl} >= 9 ) {
		print "parsing item num $item_num: '".$self->dump_line($line)."'\n";
	} elsif ( $self->{vl} >= 7 ) {
		print "parsing item num $item_num: '". $self->short_str($line) . "'\n";
	}

	return "Colons not found on begin of item $item_num" unless $line =~ m/^(\:+)/gcx;
	my $colons = $1;
	my $last_pnum = length( $colons ) - 1;

	my $item_info = {
		name => undef,
		mode => undef,
		hash => undef,
		parents => [],
	};

	foreach my $pnum (0..$last_pnum) {
		push @{$item_info->{parents}}, {
			mode => undef,
			hash => undef,
			status => undef,
		};
	}

	# mode
	foreach my $pnum (0..$last_pnum) {
		# No space before the first parent mode.
		return "Mode for parent number ".($pnum+1)." not found" unless $line =~ m/\G \s? ([0-7]{6}) /gcx;
		$item_info->{parents}[ $pnum ]{mode} = $1;
	}
	return "Mode for new item not found" unless $line =~ m/\G \s ([0-7]{6}) /gcx;
	$item_info->{mode} = $1;


	# hash
	foreach my $pnum (0..$last_pnum) {
		return "Hash for parent number ".($pnum+1)." not found" unless $line =~ m/\G \s ([0-9a-f]{40}) /gcx;
		$item_info->{parents}[ $pnum ]{hash} = $1;
	}
	return "Hash for new item not found" unless $line =~ m/\G \s ([0-9a-f]{40}) /gcx;
	$item_info->{hash} = $1;


	# status
	return "Empty char before status (change char) not found" unless $line =~ m/\G \s /gcx;
	foreach my $pnum (0..$last_pnum) {
		# ToDo - Use one_item_parser_err more.
		# Added (A), Copied (C), Deleted (D), Modified (M), Renamed (R),
		# have their type (i.e. regular file, symlink, submodule, …) changed (T),
		# are Unmerged (U), are Unknown (X), or have had their pairing Broken (B).
		return $self->one_item_parser_err(
			"Status (file change char) parent number ".($pnum+1)." not found",
			$line
		) unless $line =~ m/\G ([CR]\d{3}|[ACDMRT]) /gcx;
		my $action = $1;
		if ( my ($rc_status,$rc_ratio) = $action =~ m/^([CR])(\d{3})$/ ) {
			$item_info->{parents}[ $pnum ]{status} = $rc_status;
			$item_info->{parents}[ $pnum ]{ratio} = $rc_ratio;
		} else {
			$item_info->{parents}[ $pnum ]{status} = $action;
		}
	}

	# name
	my $next_item_str;

	if ( exists $item_info->{parents}[0]{ratio} ) {
		return $self->one_item_parser_err("Old and new name after rename not found",$line,$item_info)
			unless $line =~ m/\G \0 ([^\0]+) \0 ([^\0]+) \0? (.*?) $/gcx;
		$item_info->{org_name} = $1;
		$item_info->{name} = $2;
		$next_item_str = $3;
	} else {
		return $self->one_item_parser_err("Name not found",$line,$item_info)
			unless $line =~ m/\G \0 ([^\0]+) \0? (.*?) $/gcx;
		$item_info->{name} = $1;
		$next_item_str = $2;
	}

	print Dumper( $item_info ) if $self	->{vl} >= 9;
	return $item_info, $next_item_str;
}


sub parse_one_item_stat_begin {
	my ( $self, $line, $stat_num ) = @_;

	if ( $self->{vl} >= 9 ) {
		print "parsing stat num $stat_num: '".$self->dump_line($line)."'\n";
	} elsif ( $self->{vl} >= 7 ) {
		print "parsing stat num $stat_num: '" . $self->short_str($line) . "'\n";
	}

	my $stat = {};
	return "Added and removed lines numbers not found of stat item $stat_num"
		unless $line =~ m/\G (\d+|\-) \t (\d+|\-) \t /gcx;
	my ( $added, $removed ) = ( $1, $2 );
	$stat->{lines_added} = $added eq '-' ? undef : $added;
	$stat->{lines_removed} = $removed eq '-' ? undef : $removed;

	my $fname;
	my $new_item_str;
	if ( $line =~ /\G \0 /gcx ) {
		return "Old and new file name not found of stat item $stat_num"
			unless $line =~ /\G ([^\0]+) \0 ([^\0]+) (?:\0(.+))? $/gcx;
		$stat->{prev_file} = $1;
		$fname = $2;
		$new_item_str = $3;
	} else {
		return "File name not found of stat item $stat_num"
			unless $line =~ /\G ([^\0]+) (?:\0(.+))? $/gcx;
		$fname = $1;
		$new_item_str = $2;
	}
	return ( $fname, $stat, $new_item_str );
}


sub parse_items_log_line {
	my ( $self, $items_str ) = @_;

	my @items_info;
	my %items_stat;
	my $item_num = 1;
	my $stat_num = 1;
	my $new_items_str;
	while ( $items_str ) {

		if ( $items_str =~ /^\:/ ) {
			my $item;
			( $item, $new_items_str ) = $self->parse_one_item_begin( $items_str, $item_num );
			return $item unless ref $item eq 'HASH';
			push @items_info, $item;
			last unless $items_str;
			$item_num++;

		} else {
			my ( $fname, $item_stat );
			( $fname, $item_stat, $new_items_str ) = $self->parse_one_item_stat_begin( $items_str, $stat_num );
			return $fname unless ref $item_stat eq 'HASH';
			$items_stat{ $fname } = $item_stat;
			last unless $items_str;
			$stat_num++;
		}

		$items_str = $new_items_str;
	}

	return \@items_info, \%items_stat;
}


sub parse_person_log_line_part {
	my ( $self, $line_part ) = @_;

	if ( my ($name, $email, $gmtime, $timezone, $ts_mark, $ts_hour_offset, $ts_min_offset) = $line_part =~ /(.*) <(.*)> ([0-9]+) (([-+])([0-9]{2})([0-9]{2}))/ ) {
		return ( 1, $name, $email, $timezone, $gmtime );
	}

	return ( 0, "Error parsing '$line_part'" );
}


sub get_log {
	my ( $self, $ssh_skip_list, %args ) = @_;

	my @cmd_args = (
		'log', '--numstat', '--pretty=raw', '--raw', '-c', '-t', '--root',
		'--abbrev=40', '-z', '--date-order'
	);

	if ( exists $args{reverse} ) {
		push( @cmd_args, '--reverse' );
	}

	if ( exists $args{number_limit} ) {
		push( @cmd_args,  '-n', $args{number_limit} );
	}

	if ( exists $args{rev_range} ) {
		push( @cmd_args, $args{rev_range} );
	} elsif ( exists $args{only_rev} ) {
		push(
			@cmd_args,
			sprintf( "%s^..%s", $args{only_rev}, $args{only_rev} )
		);
	} elsif ( $args{all} ) {
		push @cmd_args,  '--all';
	}

	if ( exists $args{branch} ) {
		push( @cmd_args, '--branches', $args{branch} );
	}

	if ( exists $args{fpath} ) {
		push( @cmd_args,  '--', $args{fpath} );
	}

	my $cmd = $self->{repo}->command( @cmd_args );
	print "LogRaw cmdline: '" . join(' ', $cmd->cmdline() ) . "'\n" if $self->{vl} >= 8;


	my $line_num = 0;
	my $log = [];
	my $ac_state = 'begin';
	my $commit = undef;
	my $err_msg = undef;

	my $out_fh = $cmd->stdout;
	print "Parsing 'git log ...' output.\n" if $self->{vl} >= 4;
	PARSE_LOG: while ( my $line = <$out_fh> ) {
		$line_num++;
		print "Parsing 'git log ...' output - line $line_num.\n"
			if $self->{vl} >= 4 && $line_num % 100000 == 0;

		chomp $line;
		printf( "%3d (prev %10s): '%s'\n", $line_num, $ac_state, $self->dump_line($line) ) if $self->{vl} >= 9;

		# commit 1x
		PARSE_COMMIT_LINE:
		if ( $self->{vl} >= 9 ) {
			print "on commit: $line\n" ;
		} elsif ( $self->{vl} >= 6 ) {
			print "on commit: '". $self->short_str($line) . "'\n";
		}
		if ( my ( $nulls, $commit_hash ) = $line =~ /^(\0{0,2})commit ([0-9a-f]{40})$/ ) {
			if ( defined $commit ) {
				print Dumper( $commit ) if $self->{vl} >= 8;
				if ( (not defined $ssh_skip_list) || (not exists $ssh_skip_list->{$commit->{commit}}) ) {
					push @$log, $commit;
				}
			}

			if ( $ac_state eq 'commit_after_items' ) {
				if ( $nulls ne '' ) {
					$err_msg = "Found 'commit' begining with " . length($nulls) . " null(s) after '$ac_state'.";
					last PARSE_LOG;
				}

			} elsif ( $ac_state eq 'msg' && ($nulls eq "\0" || $nulls eq "\0\0") ) {
				# todo - one or two nulls on merge commits are ok?

			} elsif (
				   $ac_state ne 'begin'
				&& $ac_state ne 'empty_ca'
				&& $ac_state ne 'empty_af'
				&& $ac_state ne 'committer' # empty commit message, and empty commit
			) {
				$err_msg = "Found 'commit' type line after '$ac_state'.";
				last PARSE_LOG;
			}
			$commit = {
				commit => $commit_hash,
				tree => undef,
				parents => [],
				author => {
					name => undef,
					email => undef,
					timezone => undef,
					gmtime => undef,
				},
				committer => {
					name => undef,
					email => undef,
					timezone => undef,
					gmtime => undef,
				},
				msg => undef,
				items => [],
			};
			$ac_state = 'commit';
			next PARSE_LOG;
		}

		# tree 1x
		if ( my ( $tree ) = $line =~ /^tree ([0-9a-f]{40})$/ ) {
			if ( $ac_state ne 'commit' ) {
				$err_msg = "Found 'tree' type line after '$ac_state'.";
				last PARSE_LOG;
			}
			$commit->{tree} = $tree;
			$ac_state = 'tree';
			next PARSE_LOG;
		}

		# parent 0+x
		if ( my ( $parent ) = $line =~ /^parent ([0-9a-f]{40})$/ ) {
			if ( $ac_state ne 'tree' && $ac_state ne 'parent' ) {
				$err_msg = "Found 'parent' type line after '$ac_state'.";
				last PARSE_LOG;
			}
			push @{$commit->{parents}}, $parent;
			$ac_state = 'parent';
			next PARSE_LOG;
		}

		# author 1x
		if ( my ( $person_raw ) = $line =~ /^author (.*)$/ ) {
			if ( $ac_state ne 'parent' && $ac_state ne 'tree' ) {
				$err_msg = "Found 'author' type line after '$ac_state'.";
				last PARSE_LOG;
			}
			my ( $status, $name, $email, $timezone, $gmtime ) = $self->parse_person_log_line_part( $person_raw );
			if ( $status != 1 ) {
				$err_msg = "Committer line error. $name.";
				last PARSE_LOG;
			}
			$commit->{author}{name} = $name;
			$commit->{author}{email} = $email;
			$commit->{author}{timezone} = $timezone;
			$commit->{author}{gmtime} = $gmtime;
			$ac_state = 'author';
			next PARSE_LOG;
		}

		# committer 1x
		if ( my ( $person_raw ) = $line =~ /^committer (.*)$/ ) {
			if ( $ac_state ne 'author' ) {
				$err_msg = "Found 'committer' type line after '$ac_state'.";
				last PARSE_LOG;
			}
			my ( $status, $name, $email, $timezone, $gmtime ) = $self->parse_person_log_line_part( $person_raw );
			if ( $status != 1 ) {
				$err_msg = "Committer line error. $name.";
				last PARSE_LOG;
			}
			$commit->{committer}{name} = $name;
			$commit->{committer}{email} = $email;
			$commit->{committer}{timezone} = $timezone;
			$commit->{committer}{gmtime} = $gmtime;
			$ac_state = 'committer';
			next PARSE_LOG;
		}

		# ToDo before or after gpgsig?
		# ToDo explicit list? "HG:extra ", "HG:rename ","HG:rename-source "
		# HG: Xx
		if ( $line =~ /^HG:[a-z-]+ .+$/ ) {
			if ( $ac_state ne 'committer' ) {
				$err_msg = "Found 'HG:' line after '$ac_state'.";
				last PARSE_LOG;
			}
			$ac_state = 'committer';
			next PARSE_LOG;
		}

		# gpgsig 1x
		if ( my ( $gpgsig_begin ) = $line =~ /^gpgsig (.*)$/ ) {
			if ( $ac_state ne 'committer' ) {
				$err_msg = "Found 'gpgsig' type line after '$ac_state'.";
				last PARSE_LOG;
			}
			$commit->{committer}{gpgsig} = $gpgsig_begin."\n";
			$ac_state = 'gpgsig';
			next PARSE_LOG;
		}
		# gpgsig pgp signature
		if ( $ac_state eq 'gpgsig' ) {
			if ( $line =~ /-----END PGP SIGNATURE-----/ ) {
				$ac_state = 'committer';
			}
			$commit->{committer}{gpgsig} .= $line."\n";
			next PARSE_LOG;
		}

		# empty lines - 1x each type
		if ( $line eq '' ) {
			# empty_cb
			if ( $ac_state eq 'committer' ) {
				$ac_state = 'empty_cb';
				next PARSE_LOG;
			}
			# empty_ca
			if ( $ac_state eq 'msg' ) {
				$ac_state = 'empty_ca';
				next PARSE_LOG;
			}
			# empty_af
			if ( $ac_state eq 'item' || $ac_state eq 'empty_ca' ) {
				$ac_state = 'empty_af';
				next PARSE_LOG;
			}
			$err_msg = "Found empty line after '$ac_state'";
			last PARSE_LOG;
		}

		# msg/msg line - 1+x
		if ( my ( $msg_line ) = $line =~ /^ {4}(.*)$/ ) {
			if ( $ac_state ne 'empty_cb' && $ac_state ne 'msg' ) {
				$err_msg = "Found 'msg' type line after '$ac_state'.";
				last PARSE_LOG;
			}
			$commit->{msg} .= "\n" if $commit->{msg};
			$commit->{msg} .= $msg_line;
			$ac_state = 'msg';
			next PARSE_LOG;
		}

		# empty_ca 1x - code is above

		# items 0+x
		if ( $line =~ /^\0?\:+/ || $line =~ /^\0(\d+|\-)\t(\d+|\-)\t/ ) {
			my ( $items_part, $commit_part ) = split '\0\0', $line;
			$items_part =~ s{^\0}{};
			$items_part =~ s{\0$}{} unless $commit_part;

			my ( $items_info, $items_stat ) = $self->parse_items_log_line( $items_part );
			if ( ref $items_info ne 'ARRAY' ) {
				# ToDo - add commit hash to other error messages.
				$err_msg = "Item line error (commit $commit->{commit}). $items_info.\n";
				last PARSE_LOG;
			}
			$commit->{items} = $items_info;
			$commit->{stat} = $items_stat;

			# end of log
			last PARSE_LOG unless defined $commit_part;

			$ac_state = 'commit_after_items';
			$line = $commit_part;
			goto PARSE_COMMIT_LINE;
		}

		# no any items
		if ( $line eq "\0" && $ac_state eq 'msg' ) {
			$commit->{items} = undef;
			$commit->{stat} = undef;
			next PARSE_LOG;
		}

		# empty_af 1x - code is above

		# error
		$err_msg = "Can't determine line type";
		last PARSE_LOG;
	}

	if ( $err_msg ) {
		print "Parsing error on line $line_num: $err_msg\n";
		return undef;
	}

	my $err = $cmd->stderr();
	my $err_out = do { local $/; <$err> };
	if ( $err_out ) {
		$self->{err_msg} = "Error:\n  $err_out\n" . $err_msg;
		print $self->{err_msg} if $self->{vl} >= 1;
		return undef;
	}
	if ( $err_msg ) {
		$self->{err_msg} = $err_msg;
		print $self->{err_msg} if $self->{vl} >= 1;
		return undef;
	}

	print Dumper( $commit ) if $self->{vl} >= 7;
	if ( (not defined $ssh_skip_list) || (not exists $ssh_skip_list->{$commit->{commit}}) ) {
		push @$log, $commit;
	}

	$cmd->close;
	return $log;
}


sub get_err_msg {
	my ( $self ) = @_;
	return $self->{err_msg};
}



sub get_refs {
	my ( $self, $filter_type ) = @_;

	my $cmd = $self->{repo}->command( 'for-each-ref' );
	print "LogRaw cmdline: '" . join(' ', $cmd->cmdline() ) . "'\n" if $self->{vl} >= 5;

	my $line_num = 0;
	my $refs = {};
	my $err_msg = undef;

	my $out_fh = $cmd->stdout;
	PARSE_REF: while ( my $line = <$out_fh> ) {
		$line_num++;
		chomp $line;
		printf( "%3d: '%s'\n", $line_num, $line ) if $self->{vl} >= 7;

		if ( my ( $sha, $sha_type, $tag_name ) = $line =~ /^([0-9a-f]{40})\ (commit|tag)\t(.*)$/ ) {
			if ( my ( $name_prefix, $name_base ) = $tag_name =~ /^([^\/]+\/[^\/]+)\/(.*)$/ ) {
				my $ref_info = {
					sha => $sha,
					sha_type => $sha_type,
					prefix => $name_prefix,
				};
				if ( $name_prefix eq 'refs/heads' ) {
					$ref_info->{type} = 'remote_ref';
					$ref_info->{repo_alias} = 'origin';
					$ref_info->{branch_name} = $name_base;

				} elsif ( $name_prefix eq 'refs/tags' ) {
					$ref_info->{type} = 'tag';
					$ref_info->{tag_name} = $name_base;

				} else {
					$ref_info->{type} = 'unknown';
					$ref_info->{name_base} = $name_base;
				}

				next if defined $filter_type && $filter_type ne $ref_info->{type};
				$refs->{ $tag_name } = $ref_info;

			} else {
				$err_msg = "Can't split ref name '$tag_name' to parts";
				last PARSE_REF;
			}
			next;
		}

		# error
		$err_msg = "Can't parse line";
		last PARSE_REF;
	}

	if ( $err_msg ) {
		$err_msg = "Parsing error on line $line_num: $err_msg\n";
	}

	my $err = $cmd->stderr();
	my $err_out = do { local $/; <$err> };
	$cmd->close;

	if ( $err_out ) {
		$err_msg = '' unless $err_msg;
		$err_msg = "Command error:\n  $err_out\n" . $err_msg;
	}
	if ( $err_msg ) {
		$self->{err_msg} = $err_msg;
		print $self->{err_msg} if $self->{vl} >= 1;
		return undef;
	}

	return $refs;
}


1;
