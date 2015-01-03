package # hide from PAUSE
App::YTDL::Info_Print;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( linefolded_print_info );

use Encode qw( decode_utf8 );

use Term::ANSIScreen qw( :cursor :screen );
use Text::LineFold   qw();
use URI              qw();
use URI::Escape      qw( uri_unescape );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::YTDL::Data         qw( wrapper_get get_download_info_as_json );
use App::YTDL::Data_Extract qw( json_to_hash );
use App::YTDL::Helper       qw( term_size );



sub _youtube_print_info {
    my ( $opt, $info, $video_id ) = @_;
    my $message = "** GET download info: ";
    my $json = get_download_info_as_json( $opt, $video_id, $message );
    json_to_hash( $json, $info ) if $json;
    my $info_url = URI->new( 'https://www.youtube.com/get_video_info' );
    $info_url->query_form( 'video_id' => $video_id );
    my $res = wrapper_get( $opt, $info_url->as_string );
    $opt->{up}++;
    return if ! defined $res;
    for my $item ( split /&/, $res->decoded_content ) {
        my ( $key, $value ) = split /=/, $item;
        if ( defined $value && $key =~ /^(?:title|keywords|reason|status)\z/ ) {
            $info->{$video_id}{$key} = decode_utf8( uri_unescape( $value ) );
            $info->{$video_id}{$key} =~ s/\+/ /g;
            $info->{$video_id}{$key} =~ s/(?<=\p{Word}),(?=\p{Word})/, /g if $key eq 'keywords';
        }
    }
}


sub _prepare_print_info {
    my ( $opt, $info, $video_id ) = @_;
    if ( $info->{$video_id}{youtube} ) {
        _youtube_print_info( $opt, $info, $video_id );
    }
    $info->{$video_id}{published} = $info->{$video_id}{upload_date};
    $info->{$video_id}{author}    = $info->{$video_id}{uploader};
    if ( $info->{$video_id}{author} && $info->{$video_id}{uploader_id} ) {
        if ( $info->{$video_id}{author} ne $info->{$video_id}{uploader_id} ) {
            $info->{$video_id}{author} .= ' (' . $info->{$video_id}{uploader_id} . ')';
        }
    }
    my @keys = ( qw( title video_id ) );
    if ( defined $info->{$video_id}{status} && $info->{$video_id}{status} ne 'ok' ) {
        $opt->{up}++;
        print up( $opt->{up} ), cldown;
        $opt->{up} = 0;
        splice @keys, 1, 0, 'status', 'errorcode', 'reason';
    }
    push @keys, 'extractor' if ! $info->{$video_id}{youtube};
    push @keys, qw( author duration raters avg_rating view_count published content description keywords );
    for my $key ( @keys ) {
        next if ! $info->{$video_id}{$key};
        $info->{$video_id}{$key} =~ s/\R/ /g;
    }
    return @keys;
}


sub linefolded_print_info {
    my ( $opt, $info, $video_id, $key_len ) = @_;
    my @keys = _prepare_print_info( $opt, $info, $video_id );
    my $s_tab = $key_len + length( ' : ' );
    my ( $maxcols, $maxrows ) = term_size();
    $maxcols -= $opt->{right_margin};
    my $col_max = $maxcols > $opt->{max_info_width} ? $opt->{max_info_width} : $maxcols;
    my $lf = Text::LineFold->new( %{$opt->{linefold}} );
    $lf->config( 'ColMax', $col_max );
    my $print_array;
    for my $key ( @keys ) {
        next if ! length $info->{$video_id}{$key};
        $info->{$video_id}{$key} =~ s/\n+/\n/g;
        $info->{$video_id}{$key} =~ s/^\s+//;
        ( my $kk = $key ) =~ s/_/ /g;
        my $pr_key = sprintf "%*.*s : ", $key_len, $key_len, $kk;
        my $text = $lf->fold( '' , ' ' x $s_tab, $pr_key . $info->{$video_id}{$key} );
        $text =~ s/\R+\z//;
        for my $val ( split /\R+/, $text ) {
            push @$print_array, $val . "\n";
        }
    }
    # auto width:
    my $ratio = @$print_array / $maxrows;
    my $begin = 0.70;
    my $end   = 1.50;
    my $step  = 0.0125;
    my $div   = ( $end - $begin ) / $step + 1;
    my $plus;
    if ( $ratio >= $begin ) {
        $ratio = $end if $ratio > $end;
        $plus = int( ( ( $maxcols - $col_max ) / $div ) * ( ( $ratio - $begin  ) / $step + 1 ) );
    }
    if ( $plus ) {
        $col_max += $plus;
        $lf->config( 'ColMax', $col_max );
        $print_array = [];
        for my $key ( @keys ) {
            next if ! length $info->{$video_id}{$key};
            ( my $kk = $key ) =~ s/_/ /g;
            my $pr_key = sprintf "%*.*s : ", $key_len, $key_len, $kk;
            my $text = $lf->fold( '' , ' ' x $s_tab, $pr_key . $info->{$video_id}{$key} );
            $text =~ s/\R+\z//;
            for my $val ( split /\R+/, $text ) {
                push @$print_array, $val . "\n";
            }
        }
    }
    if ( @$print_array > ( $maxrows - 6 ) ) {
        $col_max = $maxcols;
        $lf->config( 'ColMax', $col_max );
        $print_array = [];
        for my $key ( @keys ) {
            next if ! length $info->{$video_id}{$key};
            ( my $kk = $key ) =~ s/_/ /g;
            my $pr_key = sprintf "%*.*s : ", $key_len, $key_len, $kk;
            my $text = $lf->fold( '' , ' ' x $s_tab, $pr_key . $info->{$video_id}{$key} );
            $text =~ s/\R+\z//;
            for my $val ( split /\R+/, $text ) {
                push @$print_array, $val . "\n";
            }
        }
    }
    return $print_array;
}





1;


__END__
