use 5.010001;
use warnings;
use strict;
use ExtUtils::MakeMaker;


my %prereqs_os_specific;
if ( $^O eq 'MSWin32' ) {
    %prereqs_os_specific = (
        'Win32::Console::ANSI' => 0,
    );
}


WriteMakefile(
    PL_FILES         => {},
    MIN_PERL_VERSION => '5.010001',
    LICENSE          => 'perl',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
              type => 'git',
              web  => 'https://github.com/kuerbis/App-YTDL',
              url  => 'https://github.com/kuerbis/App-YTDL.git',
            },
        },
    },
    AUTHOR           => 'Kuerbis <cuer2s@gmail.com>',
    NAME             => 'App::YTDL',
    VERSION_FROM     => 'lib/App/YTDL.pm',
    EXE_FILES        => [ 'bin/yt-download' ],
    BUILD_REQUIRES   => {
        'Test::More'             => 0,
    },
    PREREQ_PM => {
        'Encode'                 => 0,
        'Encode::Locale'         => 0,
        'Exporter'               => 0,
        'Fcntl'                  => 0,
        'File::Basename'         => 0,
        'File::HomeDir'          => 0,
        'File::Spec::Functions'  => 0,
        'File::Temp'             => 0,
        'FindBin'                => 0,
        'Getopt::Long'           => 0,
        'JSON::XS'               => 0,
        'List::MoreUtils'        => 0,
        'List::Util'             => 0,
        'LWP::UserAgent'         => 0,
        'Pod::Usage'             => 0,
        'Term::ANSIScreen'       => 0,
        'Term::Choose'           => '1.100',
        'Term::Size::Any'        => 0,
        'Text::LineFold'         => 0,
        'Time::HiRes'            => 0,
        'Try::Tiny'              => 0,
        'Unicode::GCString'      => 0,
        'Unicode::Normalize'     => 0,
        'URI'                    => 0,
        'URI::Escape'            => 0,
        'WWW::YouTube::Download' => 0,
        'XML::LibXML'            => 0,
        %prereqs_os_specific,
    },
    clean => {
        FILES => 'App-YTDL-*',
    },
);
