# Test in-version upgrading (usually used after catalog version bumps)

use strict;

use lib 't';
use TestLib;
use PgCommon;

use Test::More tests => 14 * length(@MAJORS);

foreach my $v (@MAJORS) {
    program_ok 0, "pg_createcluster $v main --start", 0;
    program_ok 0, "pg_upgradecluster --old-bindir=$PgCommon::binroot$v/bin -v $v --rename upgr $v main", 0;
    like_program_out 0, "pg_lsclusters -h", 0, qr/$v main 5433 down.*\n$v upgr 5432 online/;

    program_ok 0, "pg_dropcluster $v main --stop", 0;
    program_ok 0, "pg_dropcluster $v upgr --stop", 0;
    check_clean;
}

# vim: filetype=perl
