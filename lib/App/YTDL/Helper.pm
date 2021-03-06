package # hide from PAUSE
App::YTDL::Helper;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( term_size sec_to_time insert_sep unicode_trim choose_a_dir choose_a_number
                     print_hash encode_fs encode_stdout_lax encode_stdout );

use Encode             qw( encode );
use Unicode::Normalize qw( NFC );

use Encode::Locale;
use Term::Choose::Util qw( print_hash choose_a_dir choose_a_number term_size insert_sep unicode_trim );


sub encode_fs {
    my ( $filename ) = @_;
    return encode( 'locale_fs', NFC( $filename ), Encode::FB_HTMLCREF );
}


sub encode_stdout_lax {
    my ( $string ) = @_;
    return encode( 'console_out', NFC( $string ), sub { '*' } );
}


sub encode_stdout {
    my ( $string ) = @_;
    return encode( 'console_out', NFC( $string ), Encode::FB_HTMLCREF );
}


sub sec_to_time {
    my ( $seconds, $long ) = @_;
    die 'seconds: not defined'      if ! defined $seconds;
    die 'seconds: "' . $seconds . '" invalid datatype' if $seconds !~ /^[0-9]+\z/;
    my ( $minutes, $hours );
    if ( $seconds ) {
        $minutes = int( $seconds / 60 );
        $seconds = $seconds % 60;
    }
    if ( $minutes ) {
        $hours   = int( $minutes / 60 );
        $minutes = $minutes % 60;
    }
    if ( $long ) {
        return sprintf( "%d:%02d:%02d", $hours // 0, $minutes // 0, $seconds );
    }
    if ( $hours ) {
        return sprintf( "%d:%02d:%02d", $hours, $minutes, $seconds );
    }
    elsif ( $minutes ) {
        return sprintf( "%d:%02d", $minutes, $seconds );
    }
    else {
        return sprintf( "0:%02d", $seconds );
    }
}



1;


__END__
