#!/usr/bin/perl

# Compile test.

use strict;
use Test::More tests => 2;

ok( $] > 5.01000, 'Perl version is 5.010 or newer' );
use_ok( 'Git::Repository::LogRaw' );
