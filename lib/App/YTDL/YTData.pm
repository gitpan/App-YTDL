package # hide from PAUSE
App::YTDL::YTData;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( get_data get_new_video_url choose_from_list_and_add_to_info wrapper_get );

use File::Which            qw( which );
use IPC::System::Simple    qw( capture );
use JSON                   qw( decode_json );
use LWP::UserAgent         qw();
use List::MoreUtils        qw( any none );
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


sub get_data {
    my ( $opt, $info, $video_id ) = @_;
    my $youtube_dl = which( 'youtube-dl' ) // 'youtube-dl';
    my @cmd = ( $youtube_dl );
    push @cmd, '--user-agent', $opt->{useragent} if defined $opt->{useragent};
    push @cmd, '--socket-timeout', $opt->{timeout};
    #push @cmd, '-v';
    push @cmd, '--dump-json', '--', $video_id;
    my $capture;
    my $message = "** GET download info: ";
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
        };
        if ( $count > $opt->{retries} ) {
            push @{$opt->{error_get_download_infos}}, $video_id;
            return $info;
        }
        next RETRY if $not_ok;
        last;
    }
    $opt->{up}++; ##
    my @json = split /\n+/, $capture;
    my $is_list = @json > 1 ? 1 : 0;
    my $list_id;
    my $playlist_id = $info->{$video_id}{playlist_id};
    if ( $is_list ) {
        delete $info->{$video_id};
        $list_id = 'OT_' . $video_id;
    }
    else {
        $list_id = $info->{$video_id}{list_id};
    }
    my $ids;
    my $tmp = {};
    for my $json ( @json ) {
        my $h_ref = decode_json( $json );
        my $fmt_list = [];
        my $formats  = {};
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
            $video_id = $h_ref->{id} // $h_ref->{title};
        }
        push @$ids, $video_id;
        $tmp->{$video_id} = {
            video_id        => $video_id,
            id              => $h_ref->{id},
            #age_limit       => $h_ref->{age_limit},
            #annotations     => $h_ref->{annotations},
            author_raw      => $h_ref->{uploader},          # author user
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
            playlist_id     => $playlist_id,
            #playlist_index  => $h_ref->{playlist_index},
            published_raw   => $h_ref->{upload_date},       # published_raw
            #stitle          => $h_ref->{stitle},
            title           => $h_ref->{title},
            view_count      => $h_ref->{view_count},
        };
        $tmp->{$video_id}{fmt_to_info} = $formats;
        $tmp->{$video_id}{fmt_list}    = $fmt_list;
        $tmp->{$video_id}{list_id}     = $list_id;
        $tmp = _prepare_info_hash( $tmp, $video_id );
        if ( defined $tmp->{$video_id}{extractor_key} && $tmp->{$video_id}{extractor_key} =~ /^youtube\z/i) {
            $tmp->{$video_id}{youtube} = 1;
        }
    }
    if ( $is_list ) {
        $info = choose_ids_from_list( $opt, $info, $tmp, $ids );
    }
    else {
        my ( $video_id ) = keys %$tmp;
        $info->{$video_id} = $tmp->{$video_id};
    }
    return $info;
}


sub choose_from_list_and_add_to_info {
    my ( $opt, $info, $tmp, $ids ) = @_;
    my $regexp;
    my $ok     = '-OK-';
    my $close  = 'CLOSE';
    my $filter = '     FILTER';
    my $back   = '       BACK | 0:00:00';
    my $menu   = 'Your choice:';
    my %chosen_video_ids;
    my @last_chosen_video_ids = ();

    FILTER: while ( 1 ) {
        my @pre = ( $menu );
        push @pre, $filter if ! length $regexp;
        my @video_print_list;
        my @tmp_video_ids;
        my $index = $#pre;
        my $mark = [];
        my @video_ids = sort {
            ( $opt->{new_first} ? ( $tmp->{$b}{published} // '' ) cmp ( $tmp->{$a}{published} // '' )
                                : ( $tmp->{$a}{published} // '' ) cmp ( $tmp->{$b}{published} // '' ) )
                               || ( $tmp->{$a}{title}     // '' ) cmp ( $tmp->{$b}{title}     // '' ) } @$ids;


        VIDEO_ID:
        for my $video_id ( @video_ids ) {
            ( my $title = $tmp->{$video_id}{title} ) =~ s/\s+/ /g;
            $title =~ s/^\s+|\s+\z//g;
            if ( length $regexp && $title !~ /$regexp/i ) {
                next VIDEO_ID;
            }
            push @video_print_list, sprintf "%11s | %7s  %10s  %s", $video_id, $tmp->{$video_id}{duration}, $tmp->{$video_id}{published}, $title;
            push @tmp_video_ids, $video_id;
            $index++;
            push @$mark, $index if any { $video_id eq $_ } keys %chosen_video_ids;
        }
        my $choices = [ @pre, @video_print_list, undef ];
        my @idx = choose(
            $choices,
            { prompt => '', layout => 3, index => 1, default => 1, clear_screen => 1, mark => $mark,
              undef => $back, no_spacebar => [ 0 .. $#pre, $#$choices ] }
        );
        return if ! defined $idx[0];
        my $choice = $choices->[$idx[0]];
        if ( $choice eq $menu ) {
            shift @idx;
            my $menu_choice = choose(
                [ undef, $ok, $close ],
                { prompt => 'Choice: ', layout => 0, default => 0, undef => '<<' }
            );
            if ( ! defined $menu_choice ) {
                if ( length $regexp ) {
                    delete @{$info}{ @last_chosen_video_ids };
                    $regexp = '';
                    next FILTER;
                }
                else {
                    delete @{$info}{ keys %chosen_video_ids };
                    return;
                }
            }
            elsif ( $menu_choice eq $ok ) {
                @last_chosen_video_ids = ();
                for my $i ( @idx ) {
                    my $video_id = $tmp_video_ids[$i - @pre];
                    $info->{$video_id} = $tmp->{$video_id};
                    $chosen_video_ids{$video_id}++;
                    push @last_chosen_video_ids, $video_id;
                }
                for my $m ( @$mark ) {
                    if ( none { $m == $_ } @idx ) {
                        my $video_id = $tmp_video_ids[$m - @pre];
                        delete $chosen_video_ids{$video_id};
                        delete $info->{$video_id};
                    }
                }
                if ( length $regexp ) {
                    $regexp = '';
                    next FILTER;
                }
                else {
                    last FILTER;
                }
            }
            elsif ( $choice eq $close ) {
                next FILTER;
            }
        }
        elsif ( $choice eq $filter ) {
            my $trs = Term::ReadLine::Simple->new();
            $regexp = $trs->readline( "Regexp: " );
            next FILTER;
        }
        else {
            @last_chosen_video_ids = ();
            for my $i ( @idx ) {
                my $video_id = $tmp_video_ids[$i - @pre];
                $info->{$video_id} = $tmp->{$video_id};
                $chosen_video_ids{$video_id}++;
                push @last_chosen_video_ids, $video_id;
            }
            for my $m ( @$mark ) {
                if ( none { $m == $_ } @idx ) {
                    my $video_id = $tmp_video_ids[$m - @pre];
                    delete $chosen_video_ids{$video_id};
                    delete $info->{$video_id};
                }
            }
            if ( ! length $regexp ) {
                last FILTER;
            }
            $regexp = '';
            next FILTER;
        }
    }
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
    if ( $info->{$video_id}{author_raw} ) {
        $info->{$video_id}{author} = $info->{$video_id}{author_raw};
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
