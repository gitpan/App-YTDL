package # hide from PAUSE
App::YTDL::YTData;

use warnings;
use strict;
use 5.010001;

use Exporter qw( import );
our @EXPORT_OK = qw( get_data get_new_video_url choose_ids_from_list );

use File::Which         qw( which );
use IPC::System::Simple qw( capture );
use JSON                qw( decode_json );
use Term::ANSIScreen    qw( :screen );
use Term::Choose        qw( choose );
use Try::Tiny           qw( try catch );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::YTDL::GenericFunc qw( sec_to_time insert_sep );

sub HIDE_CURSOR () { "\e[?25l" }
sub SHOW_CURSOR () { "\e[?25h" }


sub get_new_video_url {
    my ( $opt, $info, $video_id ) = @_;
    my $fmt = $info->{$video_id}{fmt};
    my $youtube_dl = which( 'youtube-dl' ) // 'youtube-dl';
    my @cmd = ( $youtube_dl );
    push @cmd, '--user-agent', $opt->{useragent} if defined $opt->{useragent};
    #push @cmd, '-v';
    push @cmd, '--format', $fmt, '--get-url', '--', $video_id;
    my $video_url = capture( @cmd );
    return $video_url;
}


sub get_data {
    my ( $opt, $info, $video_id ) = @_;
    my $youtube_dl = which( 'youtube-dl' ) // 'youtube-dl';
    my @cmd = ( $youtube_dl );
    push @cmd, '--user-agent', $opt->{useragent} if defined $opt->{useragent};
    #push @cmd, '-v';
    push @cmd, '--dump-json', '--', $video_id;
    my $capture;
    my $message = "** GET download info: ";
    my $spinner;
    try {
        require Term::Twiddle;
        $spinner = Term::Twiddle->new();
    }
    catch {
        $spinner = undef;
    };
    if ( $spinner ) {
        print HIDE_CURSOR;
        print $message;
        $spinner->thingy( [ "[\\]", "[|]", "[/]", "[-]" ] );
        $spinner->start;
        $capture = capture( @cmd );
        $spinner->stop;
        print "\r", clline;
        print $message . "done.\n";
        print SHOW_CURSOR;
    }
    else {
        print $message . "...";
        $capture = capture( @cmd );
        print "\r", clline;
        print $message . "done.\n";
    }
    $opt->{up}++;
    my @json = split /\n+/, $capture;
    my $ids;
    my $is_list = @json > 1 ? 1 : 0;
    if ( $is_list ) {
        delete $info->{$video_id};
    }
    my $tmp = {};
    for my $json ( @json ) {
        my $h_ref = decode_json( $json );
        my $fmt_list;
        my $formats;
        for my $format ( @{$h_ref->{formats}} ) {
            my $format_id = $format->{format_id};           # fmt
            push @$fmt_list, $format_id;
            $formats->{$format_id}{ext}         = $format->{ext};
            $formats->{$format_id}{format}      = $format->{format};
            $formats->{$format_id}{format_note} = $format->{format_note};
            $formats->{$format_id}{height}      = $format->{height};
            $formats->{$format_id}{width}       = $format->{width};
            $formats->{$format_id}{url}         = $format->{url};
        }
        if ( $is_list ) {
            $video_id = $h_ref->{id};
        }
        push @$ids, $video_id;
        $tmp->{$video_id} = {
            #is_list         => $is_list,
            video_id        => $video_id,
            id              => $h_ref->{id},
            #age_limit       => $h_ref->{age_limit},
            #annotations     => $h_ref->{annotations},
            author          => $h_ref->{uploader},          # author user
            categories      => $h_ref->{categories},
            channel_id      => $h_ref->{uploader_id},       # channel_id
            description     => $h_ref->{description},
            default_fmt     => $h_ref->{format_id},
            dislike_count   => $h_ref->{dislike_count},
            duration_raw    => $h_ref->{duration},          # duration_raw
            extractor       => $h_ref->{extractor},
            extractor_key   => $h_ref->{extractor_key},
            #fulltitle       => $h_ref->{fulltitle},
            like_count      => $h_ref->{like_count},
            playlist        => $h_ref->{playlist},
            #playlist_index  => $h_ref->{playlist_index},
            published_raw   => $h_ref->{upload_date},       # published_raw
            #stitle          => $h_ref->{stitle},
            title           => $h_ref->{title},
            view_count      => $h_ref->{view_count},

            fmt_to_info      => $formats,
            fmt_list         => $fmt_list,
        };
        $tmp = _prepare_info_hash( $tmp, $video_id );
        if ( defined $tmp->{$video_id}{extractor_key} && $tmp->{$video_id}{extractor_key} =~ /^youtube\z/i) {
            $tmp->{$video_id}{youtube} = 1;
        }
    }
    if ( $is_list ) {
        $info = choose_ids_from_list( $opt, $info, $tmp, $ids ); # untested
    }
    else {
        my ( $video_id ) = keys %$tmp;
        $info->{$video_id} = $tmp->{$video_id};
    }
    return $info;
}


sub choose_ids_from_list {
    my ( $opt, $info, $tmp, $ids ) = @_;
    my @video_print_list;
    my @video_ids = grep { $_ ne $opt->{back} }
                    sort {    ( $tmp->{$a}{published} // '' ) cmp ( $tmp->{$b}{published} // '' )
                           || ( $tmp->{$a}{title}     // '' ) cmp ( $tmp->{$b}{title}     // '' ) } @$ids;
    for my $video_id ( @video_ids, $opt->{back} ) {
        ( my $title = $tmp->{$video_id}{title} ) =~ s/\s+/ /g;
        $title =~ s/^\s+|\s+\z//g;
        push @video_print_list, sprintf "%11s | %7s  %10s  %s", $video_id, $tmp->{$video_id}{duration},
                                                                $tmp->{$video_id}{published}, $title;
    }
    my @idx = choose(
        [ @video_print_list ],
        { prompt => 'Your choice: ', layout => 3, index => 1, clear_screen => 1, no_spacebar => [ $#video_print_list ] }
    );
    return if ! @idx || ! defined $idx[0] || $idx[0] == $#video_print_list;
    for my $i ( @idx ) {
        my $video_id = $video_ids[$i];
        $info->{$video_id} = $tmp->{$video_id};
    }
    return $info;
}


sub _prepare_info_hash {
    my ( $info, $video_id ) = @_;
    if ( defined $info->{$video_id}{duration_raw} ) {
        if ( $info->{$video_id}{duration_raw} =~ /^[0-9]+\z/ ) {
            $info->{$video_id}{duration} = sec_to_time( $info->{$video_id}{duration_raw}, 1 );
        }
        else {
            $info->{$video_id}{duration} = $info->{$video_id}{duration_raw};
        }
    }
    if ( $info->{$video_id}{published_raw} ) {
        if ( $info->{$video_id}{published_raw} =~ /^(\d{4})(\d{2})(\d{2})\z/ ) {
            $info->{$video_id}{published} = $1 . '-' . $2 . '-' . $3;
        }
        else {
            $info->{$video_id}{published} = $info->{$video_id}{published_raw};
        }
    }
    if ( $info->{$video_id}{channel_id} ) {
        if ( ! $info->{$video_id}{author} ) {
            $info->{$video_id}{author} = $info->{$video_id}{channel_id};
        }
        elsif ( $info->{$video_id}{author} ne $info->{$video_id}{channel_id} ) {
            $info->{$video_id}{author} .= ' (' . $info->{$video_id}{channel_id} . ')';
        }
    }
    if ( $info->{$video_id}{like_count} && $info->{$video_id}{dislike_count} ) {
        $info->{$video_id}{raters} = $info->{$video_id}{like_count} + $info->{$video_id}{dislike_count};
        $info->{$video_id}{avg_rating} = $info->{$video_id}{like_count} * 5 / $info->{$video_id}{raters};
        $info->{$video_id}{avg_rating} = sprintf "%.2f", $info->{$video_id}{avg_rating};
        $info->{$video_id}{raters} = insert_sep( $info->{$video_id}{raters} );
    }
    if ( $info->{$video_id}{view_count} ) {
        $info->{$video_id}{view_count} = insert_sep( $info->{$video_id}{view_count} );
    }
    if ( defined $info->{$video_id}{extractor} || defined $info->{$video_id}{extractor_key} ) {
        $info->{$video_id}{extractor}     = $info->{$video_id}{extractor_key} if ! defined $info->{$video_id}{extractor};
        $info->{$video_id}{extractor_key} = $info->{$video_id}{extractor}     if ! defined $info->{$video_id}{extractor_key};
    }
    return $info;
}





1;


__END__
