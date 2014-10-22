use 5.010001;
use strict;
use warnings;


use Test::Whitespaces {

    dirs => [
        'bin',
        'lib',
        't',
        'xt',
    ],

    files => [
        'README',
        'Makefile.PL',
        'Changes',
    ],

};
