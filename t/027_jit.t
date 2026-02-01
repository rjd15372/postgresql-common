use strict;

use lib 't';
use TestLib;

use Test::More;

if (! TestLib::have_jit()) {
    ok 1, "No JIT tests on this architecture";
    done_testing();
    exit;
}

my ($os, $osversion) = os_release();

foreach my $v (@MAJORS) {
    if ($v < 11) {
        ok 1, "No JIT support on $v";
        next;
    }
    note "$v";

    program_ok 'root', "pg_createcluster $v main --start", 0;

    my $jit_default = $v == '11' ? 'off' : 'on';
    like_program_out 'postgres', "psql -Xatc 'show jit'", 0, qr/$jit_default/, "JIT is $jit_default by default";
    unlike_program_out 'postgres', "psql -c 'explain (analyze) select count(*) from pg_class'", 0, qr/JIT/,
        "No JIT on cheap query";

    my $run_jit_test = 1;
    if ($v <= 13) {
        my $deps = `dpkg-query --showformat '\${Depends}' --show postgresql-$v`;
        if ($deps !~ /libllvm/) {
            note "skip JIT tests on EOL versions that are incompatible with newer LLVM";
            $run_jit_test = 0;
        }
    } elsif ($v >= 18) {
        my $f = $ENV{'PG_FLAVOR'} // '';
        my $jit_deb = "postgresql-$v$f-jit";
        if (deb_installed($jit_deb)) {
            note "$jit_deb is installed";
        } else {
            note "$jit_deb is not installed, skipping JIT tests";
            $run_jit_test = 0;
        }
    }

    if ($run_jit_test) {
        program_ok 'root', "pg_conftool $v main set jit on", 0; # turn it on for PG11
        program_ok 'root', "pg_conftool $v main set seq_page_cost 100000", 0;
        program_ok 'root', "pg_conftool $v main set random_page_cost 100000", 0;
        program_ok 'root', "pg_ctlcluster $v main reload", 0;
        like_program_out 'postgres', "psql -c 'explain (analyze) select count(*) from pg_class'", 0, qr/Timing: Generation .* ms/,
            "Expensive query is JITed";
    }

    program_ok 'root', "pg_dropcluster --stop $v main", 0;
    check_clean;
}

done_testing();

# vim: filetype=perl
