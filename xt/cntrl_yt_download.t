use 5.010000;
use strict;
use warnings;
use File::Basename qw(basename);
use Test::More;


my @files = ( qw(
    bin/yt-download
    lib/App/YTDL.pm
    lib/App/YTDL/Config.pm
    lib/App/YTDL/Data.pm
    lib/App/YTDL/Data_Extract.pm
    lib/App/YTDL/Download.pm
    lib/App/YTDL/Info.pm
    lib/App/YTDL/Videos.pm
) );


for my $file ( @files ) {
    my $data_dumper   = 0;
    my $warnings      = 0;
    my $use_lib       = 0;
    my $warn_to_fatal = 0;

    open my $fh, '<', $file or die $!;
    while ( my $line = readline $fh ) {
        if ( $line =~ /^\s*use\s+Data::Dumper/s ) {
            $data_dumper++;
        }
        if ( $line =~ /^\s*use\s+warnings\s+FATAL/s ) {
            $warnings++;
        }
        if ( $line =~ /^\s*use\s+lib\s/s ) {
            $use_lib++;
        }
        if ( $line =~ /__WARN__/s ) {
            $warn_to_fatal++;
        }
    }
    close $fh;

    is( $data_dumper,   0, 'OK - Data::Dumper in "'         . basename( $file ) . '" disabled.' );
    is( $warnings,      0, 'OK - warnings FATAL in "'       . basename( $file ) . '" disabled.' );
    is( $use_lib,       0, 'OK - no "use lib" in "'         . basename( $file ) . '"' );
    is( $warn_to_fatal, 0, 'OK - no "warn to fatal" in "'   . basename( $file ) . '"' );
}


done_testing();
