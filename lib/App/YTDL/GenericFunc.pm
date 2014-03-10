package # hide from PAUSE
App::YTDL::GenericFunc;

use warnings;
use strict;
use 5.10.1;

use Exporter qw( import );
our @EXPORT_OK = qw( term_size sec_to_time insert_sep unicode_trim encode_fs encode_stdout_lax encode_stdout );

use Encode             qw( encode );
use Unicode::Normalize qw( NFC );

use Encode::Locale;
use Term::Size::Any    qw( chars );
use Unicode::GCString;


sub term_size {
    my ( $handle_out ) = @_;
    $handle_out //= \*STDOUT;
    my ( $width, $height ) = chars( $handle_out );
    return $width - 1, $height if $^O eq 'MSWin32';
    return $width, $height;
}

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


sub insert_sep {
    my ( $number ) = @_;
    $number =~ s/(\d)(?=(?:\d{3})+\b)/$1,/g;
    return $number;
}


sub unicode_trim {
    my ( $unicode, $len ) = @_;
    return '' if $len <= 0;
    my $gcs = Unicode::GCString->new( $unicode );
    my $pos = $gcs->pos;
    $gcs->pos( 0 );
    my $cols = 0;
    my $gc;
    while ( defined( $gc = $gcs->next ) ) {
        if ( $len < ( $cols += $gc->columns ) ) {
            my $ret = $gcs->substr( 0, $gcs->pos - 1 );
            $gcs->pos( $pos );
            return $ret->as_string;
        }
    }
    $gcs->pos( $pos );
    return $gcs->as_string;
}



1;


__END__
