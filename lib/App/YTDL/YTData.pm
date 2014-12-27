package # hide from PAUSE
App::YTDL::YTData;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( get_data get_new_video_url non_yt_id_to_info_hash wrapper_get prepare_info_hash );

use File::Which            qw( which );
use IPC::System::Simple    qw( capture );
use JSON                   qw( decode_json );
use LWP::UserAgent         qw();
use Term::ANSIScreen       qw( :screen );
use Term::Choose           qw( choose );
use Term::ReadLine::Simple qw();
use Try::Tiny              qw( try catch );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::YTDL::GenericFunc qw( sec_to_time insert_sep );

sub HIDE_CURSOR () { "\e[?25l" }
sub SHOW_CURSOR () { "\e[?25h" }


sub wrapper_get {
    my ( $opt, $info, $url ) = @_;
    my $show_progress = 1;
    my $ua = LWP::UserAgent->new( agent => $opt->{useragent}, timeout => $opt->{timeout}, show_progress => $show_progress );
    my $res;
    my $count = 1;
    RETRY: while ( 1 ) {
        my $not_ok;
        try {
            $res = $ua->get( $url );
            die $res->status_line, ': ', $url if ! $res->is_success;
        }
        catch {
            if ( $count > $opt->{retries} ) {
                return;
            }
            say "$count/$opt->{retries}  $_";
            $count++;
            $not_ok = 1;
            sleep $opt->{retries} * 2;
        };
        next RETRY if $not_ok;
        return $res;
    }
}


sub get_new_video_url {
    my ( $opt, $info, $video_id ) = @_;
    my $fmt = $info->{$video_id}{fmt};
    my $youtube_dl = which( 'youtube-dl' ) // 'youtube-dl';
    my @cmd = ( $youtube_dl );
    push @cmd, '--user-agent', $opt->{useragent} if defined $opt->{useragent};
    push @cmd, '--socket-timeout', $opt->{timeout};
    #push @cmd, '-v';
    push @cmd, '--format', $fmt, '--get-url', '--', $video_id;
    my $video_url;
    try {
        $video_url = capture( @cmd );
    }
    catch {
        say $_;
        $video_url = undef;
    };
    return $video_url;
}


sub _get_json_download_info {
    my ( $opt, $video_id, $message ) = @_;
    my $youtube_dl = which( 'youtube-dl' ) // 'youtube-dl';
    my @cmd = ( $youtube_dl );
    push @cmd, '--user-agent', $opt->{useragent} if defined $opt->{useragent};
    push @cmd, '--socket-timeout', $opt->{timeout};
    #push @cmd, '-v';
    push @cmd, '--dump-json', '--', $video_id;
    my $capture;
    my $count = 1;
    RETRY: while ( 1 ) {
        my $not_ok;
        try {
            print HIDE_CURSOR;
            print $message . '...';
            $capture = capture( @cmd );
            print "\r", clline;
            print $message . "done.\n";
            print SHOW_CURSOR;
            die if ! defined $capture;
        }
        catch {
            say "$count/$opt->{retries}  $_";
            $count++;
            $not_ok = 1;
            print SHOW_CURSOR;
            sleep $opt->{retries} * 2;
        };
        if ( $count > $opt->{retries} ) {
            push @{$opt->{error_get_download_infos}}, $video_id;
            return;
        }
        next RETRY if $not_ok;
        last;
    }
    $opt->{up}++; ##
    return $capture;
}


sub _json_to_hash {
    my ( $json, $tmp ) = @_;
    my $h_ref = decode_json( $json );
    my $formats  = {};
    for my $format ( @{$h_ref->{formats}} ) {
        my $format_id = $format->{format_id}; # fmt
        $formats->{$format_id}{ext}         = $format->{ext};
        $formats->{$format_id}{format}      = $format->{format};
        $formats->{$format_id}{format_note} = $format->{format_note};
        $formats->{$format_id}{height}      = $format->{height};
        $formats->{$format_id}{width}       = $format->{width};
        $formats->{$format_id}{url}         = $format->{url};
    }
    my $video_id = $h_ref->{id} // $h_ref->{title};
    $tmp->{$video_id} = {
        video_id        => $video_id,
        #id              => $h_ref->{id},
        #age_limit       => $h_ref->{age_limit},
        #annotations     => $h_ref->{annotations},
        author_raw      => $h_ref->{uploader},
        categories      => $h_ref->{categories},
        channel_id      => $h_ref->{uploader_id},
        description     => $h_ref->{description},
        default_fmt     => $h_ref->{format_id},
        dislike_count   => $h_ref->{dislike_count},
        duration_raw    => $h_ref->{duration},
        extractor       => $h_ref->{extractor},
        extractor_key   => $h_ref->{extractor_key},
        #fulltitle       => $h_ref->{fulltitle},
        like_count      => $h_ref->{like_count},
        #playlist        => $h_ref->{playlist},
        playlist_id     => $h_ref->{playlist_id},
        published_raw   => $h_ref->{upload_date},
        #stitle          => $h_ref->{stitle},
        title           => $h_ref->{title},
        view_count      => $h_ref->{view_count},
    };
    if ( $tmp->{$video_id}{published_raw} && $tmp->{$video_id}{published_raw} =~ /^(\d{4})(\d{2})(\d{2})\z/ ) {
            $tmp->{$video_id}{published} = $1 . '-' . $2 . '-' . $3;
    }
    $tmp->{$video_id}{fmt_to_info} = $formats;
    prepare_info_hash( $tmp, $video_id );
    if ( defined $tmp->{$video_id}{extractor_key} && $tmp->{$video_id}{extractor_key} =~ /^youtube\z/i ) {
        $tmp->{$video_id}{youtube} = 1;
    }
    return $tmp;
}


sub non_yt_id_to_info_hash {
    my ( $opt, $id ) = @_;
    my $tmp = {};
    my $message = "Fetching download info: ";
    my $json_all = _get_json_download_info( $opt, $id, $message );
    return $tmp if ! $json_all; #
    my @json = split /\n+/, $json_all;
    for my $json ( @json ) {
        $tmp = _json_to_hash( $json, $tmp );
    }
    return $tmp;
}


sub get_data {
    my ( $opt, $info, $video_id ) = @_;
    my $tmp = {};
    my $message = "** GET download info: ";
    my $json = _get_json_download_info( $opt, $video_id, $message );
    return $tmp if ! $json; #
    $tmp = _json_to_hash( $json, $tmp );
    if ( defined $info->{$video_id}{playlist_id} ) {
        $tmp->{$video_id}{playlist_id} = $info->{$video_id}{playlist_id};
    }
    $tmp->{$video_id}{from_list} = $info->{$video_id}{from_list};
    $info->{$video_id} = $tmp->{$video_id};
    return $info;
}


sub prepare_info_hash {
    my ( $info, $video_id ) = @_;
    if ( $info->{$video_id}{duration_raw} ) {
        if ( $info->{$video_id}{duration_raw} =~ /^[0-9]+\z/ ) {
            $info->{$video_id}{duration} = sec_to_time( $info->{$video_id}{duration_raw}, 1 );
        }
        else {
            $info->{$video_id}{duration} = $info->{$video_id}{duration_raw};
        }
    }
    else {
        $info->{$video_id}{duration} = '-:--:--';
    }
    if ( ! $info->{$video_id}{published} ) {
        if ( $info->{$video_id}{published_raw} ) {
            $info->{$video_id}{published} = $info->{$video_id}{published_raw};
        }
        else {
            $info->{$video_id}{published} = '0000-00-00';
        }
    }
    if ( $info->{$video_id}{author_raw} ) {
        $info->{$video_id}{author} = $info->{$video_id}{author_raw};
    }
    if ( ! $info->{$video_id}{channel_id} ) {
        $info->{$video_id}{channel_id} = $info->{$video_id}{playlist_id};
    }
    if ( $info->{$video_id}{channel_id} ) {
        if ( ! $info->{$video_id}{author} ) {
            $info->{$video_id}{author} = $info->{$video_id}{channel_id};
        }
        else {
            if ( $info->{$video_id}{author} ne $info->{$video_id}{channel_id} ) {
                $info->{$video_id}{author} .= ' (' . $info->{$video_id}{channel_id} . ')';
            }
        }
    }
    if ( $info->{$video_id}{like_count} && $info->{$video_id}{dislike_count} ) {
        if ( ! $info->{$video_id}{raters} ) {
            $info->{$video_id}{raters} = $info->{$video_id}{like_count} + $info->{$video_id}{dislike_count};
        }
        if ( ! $info->{$video_id}{avg_rating} ) {
            $info->{$video_id}{avg_rating} = $info->{$video_id}{like_count} * 5 / $info->{$video_id}{raters};
        }
    }
    if ( $info->{$video_id}{avg_rating} ) {
        $info->{$video_id}{avg_rating} = sprintf "%.2f", $info->{$video_id}{avg_rating};
    }
    if ( $info->{$video_id}{raters} ) {
        $info->{$video_id}{raters} = insert_sep( $info->{$video_id}{raters} );
    }
    if ( $info->{$video_id}{view_count} ) {
        $info->{$video_id}{view_count} = insert_sep( $info->{$video_id}{view_count} );
    }
    if ( defined $info->{$video_id}{extractor} || defined $info->{$video_id}{extractor_key} ) {
        $info->{$video_id}{extractor}     = $info->{$video_id}{extractor_key} if ! defined $info->{$video_id}{extractor};
        $info->{$video_id}{extractor_key} = $info->{$video_id}{extractor}     if ! defined $info->{$video_id}{extractor_key};
    }
}





1;


__END__
