use strict;
use warnings;
use Test::PerlTidy;

run_tests(
    exclude => [
        qr{Makefile.PL}, qr{twtxt-roster-.*},
        qr{blib/},       qr{.build/},
        qr{.git/}
    ]
);
