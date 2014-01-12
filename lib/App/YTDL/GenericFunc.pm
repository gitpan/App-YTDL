package # hide from PAUSE
App::YTDL::GenericFunc;

use warnings;
use strict;
use 5.10.1;
use utf8;

use Exporter qw(import);
our @EXPORT_OK = qw(sec_to_time insert_sep unicode_trim encode_filename);

use Encode qw(encode);

use Unicode::GCString;

my $encoding;

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        require Win32::API;
        Win32::API->Import('kernel32', 'UINT GetACP()');
        $encoding = 'cp'.GetACP();
    }
    else {
        $encoding = 'utf-8';
    }
}

sub encode_filename {
    my ( $file ) = @_;
    return encode( $encoding, $file );
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
